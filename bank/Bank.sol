// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import "../interfaces/IBank.sol";
import "../interfaces/IPriceOracle.sol";
import "../interfaces/IOUSDERC20.sol";
import "../interfaces/IBankSafe.sol";
import "../interfaces/IProfitController.sol";
import "../common/OnlyArbitrager.sol";
import "../common/EnableSwap.sol";
import "../libraries/Babylonian.sol";
import "./BankStates.sol";
import "./BankRecollatStates.sol";
import "./BankSafe.sol";

contract Bank is
    IBank,
    Initializable,
    BankStates,
    BankRecollatStates,
    OnlyArbitrager,
    EnableSwap
{
    using SafeERC20 for IERC20;
    using SafeERC20 for IOrcusERC20;

    // Variables
    IERC20 public collat;
    IOrcusERC20 public ousd;
    IOrcusERC20 public oru;
    IUniswapV2Pair public oruPair;
    IPriceOracle public oracle;
    IBankSafe public safe;
    IProfitController public profitController;
    address public dustbin;

    uint256 public override tcr = TCR_MAX;
    uint256 public override ecr = tcr;

    mapping(address => uint256) public redeemOruBal;
    mapping(address => uint256) public redeemCollatBal;
    mapping(address => uint256) public lastRedeemed;
    uint256 public unclaimedOru;
    uint256 public override unclaimedCollat;

    event RatioUpdated(uint256 tcr, uint256 ecr);
    event ZapSwapped(uint256 collatAmt, uint256 lpAmount);
    event Recollateralized(uint256 collatIn, uint256 oruOut);
    event LogMint(
        uint256 collatIn,
        uint256 oruIn,
        uint256 ousdOut,
        uint256 ousdFee
    );
    event LogRedeem(
        uint256 ousdIn,
        uint256 collatOut,
        uint256 ousdOut,
        uint256 ousdFee
    );

    function init(
        address _collat,
        address _ousd,
        address _oru,
        address _oruPair,
        address _oracle,
        address _safe,
        address _dustbin,
        address _arbitrager,
        address _profitController,
        address _swapController,
        uint256 _tcr
    ) public initializer onlyOwner {
        require(
            _collat != address(0) &&
                _ousd != address(0) &&
                _oru != address(0) &&
                _oracle != address(0) &&
                _safe != address(0),
            "Bank: invalid address"
        );

        collat = IERC20(_collat);
        ousd = IOrcusERC20(_ousd);
        oru = IOrcusERC20(_oru);
        oruPair = IUniswapV2Pair(_oruPair);
        oracle = IPriceOracle(_oracle);
        safe = IBankSafe(_safe);
        dustbin = _dustbin;
        profitController = IProfitController(_profitController);
        tcr = _tcr;
        blockTimestampLast = _currentBlockTs();

        // Init for OnlyArbitrager
        setArbitrager(_arbitrager);

        setSwapController(_swapController);
    }

    function setContracts(
        address _safe,
        address _dustbin,
        address _profitController,
        address _oracle
    ) public onlyOwner {
        require(
            _safe != address(0) &&
                _dustbin != address(0) &&
                _profitController != address(0) &&
                _oracle != address(0),
            "Bank: Address zero"
        );

        safe = IBankSafe(_safe);
        dustbin = _dustbin;
        profitController = IProfitController(_profitController);
        oracle = IPriceOracle(_oracle);
    }

    // Public functions
    function calcEcr() public view returns (uint256) {
        if (!enableEcr) {
            return tcr;
        }
        uint256 _totalCollatValueE18 = (totalCollatAmt() *
            MISSING_PRECISION *
            oracle.collatPrice()) / PRICE_PRECISION;

        uint256 _ecr = (_totalCollatValueE18 * RATIO_PRECISION) /
            ousd.totalSupply();
        _ecr = Math.max(_ecr, ecrMin);
        _ecr = Math.min(_ecr, ECR_MAX);

        return _ecr;
    }

    function totalCollatAmt() public view returns (uint256) {
        return
            safe.investingAmt() +
            collat.balanceOf(address(safe)) -
            unclaimedCollat;
    }

    function update() public nonReentrant {
        require(!updatePaused, "Bank: update paused");

        uint64 _timeElapsed = _currentBlockTs() - blockTimestampLast; // Overflow is desired
        require(_timeElapsed >= updatePeriod, "Bank: update too soon");

        uint256 _ousdPrice = oracle.ousdPrice();

        if (_ousdPrice > TARGET_PRICE + priceBand) {
            tcr = Math.max(tcr - tcrMovement, tcrMin);
        } else if (_ousdPrice < TARGET_PRICE - priceBand) {
            tcr = Math.min(tcr + tcrMovement, TCR_MAX);
        }

        ecr = calcEcr();
        blockTimestampLast = _currentBlockTs();
        emit RatioUpdated(tcr, ecr);
    }

    function mint(
        uint256 _collatIn,
        uint256 _oruIn,
        uint256 _ousdOutMin
    ) external onlyNonContract nonReentrant {
        require(!mintPaused, "Bank: mint paused");
        require(_collatIn > 0, "Bank: _collatIn <= 0");

        // Don't take in more collateral than the pool ceiling for this token allows
        require(
            (safe.globalCollateralBalance() + _collatIn) <= poolCeiling,
            "Bank: Pool Ceiling"
        );

        uint256 _collatPrice = oracle.collatPrice();
        uint256 _collatValueE18 = (_collatIn *
            MISSING_PRECISION *
            _collatPrice) / PRICE_PRECISION;
        uint256 _ousdOut = (_collatValueE18 * RATIO_PRECISION) / tcr;
        uint256 _requiredOruAmt = 0;
        uint256 _oruPrice = oracle.oruPrice();



        if (tcr < TCR_MAX) {
            _requiredOruAmt =
                ((_ousdOut - _collatValueE18) * PRICE_PRECISION) /
                _oruPrice;

        }

        uint256 _ousdFee = (_ousdOut * mintFee) / RATIO_PRECISION;
        _ousdOut = _ousdOut - _ousdFee;
        require(_ousdOut >= _ousdOutMin, "Bank: slippage");

        if (_requiredOruAmt > 0) {
            require(_oruIn >= _requiredOruAmt, "Bank: not enough ORU");


            // swap all Orus to Oru/Usdc LP
            uint256 _minCollatAmt = (_requiredOruAmt *
                _oruPrice *
                PRICE_PRECISION *
                (RATIO_PRECISION - zapSlippage)) /
                RATIO_PRECISION /
                PRICE_PRECISION /
                _collatPrice /
                2 /
                MISSING_PRECISION;

            oru.safeTransferFrom(msg.sender, address(this), _requiredOruAmt);
            oru.safeApprove(address(swapController), 0);
            oru.safeApprove(address(swapController), _requiredOruAmt);

            uint256 _lpAmount = swapController.zapInOru(
                _requiredOruAmt,
                _minCollatAmt,
                0
            );

            // transfer all lp token to Dustbin
            IERC20 lpToken = IERC20(address(oruPair));
            lpToken.safeTransfer(dustbin, _lpAmount);
        }

        collat.safeTransferFrom(msg.sender, address(safe), _collatIn);
        ousd.mintByBank(msg.sender, _ousdOut);
        ousd.mintByBank(address(profitController), _ousdFee);

        emit LogMint(_collatIn, _oruIn, _ousdOut, _ousdFee);
    }

    function zapMint(uint256 _collatIn, uint256 _ousdOutMin)
        public
        onlyNonContract
        nonReentrant
    {
        require(!zapMintPaused, "Bank: zap mint paused");
        require(_collatIn > 0, "Bank: _collatIn <= 0");

        // Don't take in more collateral than the pool ceiling for this token allows
        require(
            (safe.globalCollateralBalance() + _collatIn) <= poolCeiling,
            "Bank: Pool Ceiling"
        );

        uint256 _collatPrice = oracle.collatPrice();

        uint256 _collatFee = ((_collatIn * mintFee) / RATIO_PRECISION);
        uint256 _ousdFee = (_collatFee * MISSING_PRECISION * _collatPrice) /
            PRICE_PRECISION;
        uint256 _collatToMint = _collatIn - _collatFee;
        uint256 _collatToMintE18 = _collatToMint * MISSING_PRECISION;

        uint256 _oruPrice = oracle.oruPrice();
        uint256 _collatToBuy = 0;
        if (tcr < TCR_MAX) {
            _collatToBuy = _collatAmtToBuyShare(
                _collatToMint,
                _collatPrice,
                _oruPrice
            );
            _collatToMintE18 -= (_collatToBuy * MISSING_PRECISION);
        }

        collat.safeTransferFrom(msg.sender, address(this), _collatIn);
        uint256 _lpAmount = 0;
        if (_collatToBuy > 0) {
            collat.safeApprove(address(swapController), 0);
            collat.safeApprove(address(swapController), _collatToBuy);

            uint256 _minOruAmt = (_collatToBuy *
                PRICE_PRECISION *
                (RATIO_PRECISION - zapSlippage)) /
                _oruPrice /
                RATIO_PRECISION /
                2;

            _lpAmount = swapController.zapInUsdc(_collatToBuy, _minOruAmt, 0);
            _collatToMintE18 = (_collatToMintE18 * RATIO_PRECISION) / tcr;
            emit ZapSwapped(_collatToBuy, _lpAmount);
        }

        uint256 _ousdOut = (_collatToMintE18 * _collatPrice) / PRICE_PRECISION;
        require(_ousdOut >= _ousdOutMin, "Bank: oUSD slippage");

        if (_lpAmount > 0) {
            // transfer all lp token to Dustbin
            IERC20 lpToken = IERC20(address(oruPair));
            lpToken.safeTransfer(dustbin, lpToken.balanceOf(address(this)));
        }
        collat.safeTransfer(address(safe), collat.balanceOf(address(this)));
        ousd.mintByBank(msg.sender, _ousdOut);
        ousd.mintByBank(address(profitController), _ousdFee);

        emit LogMint(_collatIn, 0, _ousdOut, _ousdFee);
    }

    function redeem(
        uint256 _ousdIn,
        uint256 _oruOutMin,
        uint256 _collatOutMin
    ) external onlyNonContract nonReentrant {
        require(!redeemPaused, "Bank: redeem paused");
        require(_ousdIn > 0, "Bank: ousd <= 0");

        uint256 _ousdFee = (_ousdIn * redeemFee) / RATIO_PRECISION;
        uint256 _ousdToRedeem = _ousdIn - _ousdFee;
        uint256 _oruOut = 0;
        uint256 _collatOut = (_ousdToRedeem * PRICE_PRECISION) /
            oracle.collatPrice() /
            MISSING_PRECISION;

        if (ecr < ECR_MAX) {
            uint256 _oruOutValue = _ousdToRedeem -
                ((_ousdToRedeem * ecr) / RATIO_PRECISION);
            _oruOut = (_oruOutValue * PRICE_PRECISION) / oracle.oruPrice();
            _collatOut = (_collatOut * ecr) / RATIO_PRECISION;
        }

        require(
            _collatOut <= totalCollatAmt(),
            "Bank: insufficient bank balance"
        );
        require(_collatOut >= _collatOutMin, "Bank: collat slippage");
        require(_oruOut >= _oruOutMin, "Bank: oru slippage");

        if (_collatOut > 0) {
            redeemCollatBal[msg.sender] += _collatOut;
            unclaimedCollat += _collatOut;
        }

        if (_oruOut > 0) {
            redeemOruBal[msg.sender] += _oruOut;
            unclaimedOru += _oruOut;
            oru.mintByBank(address(safe), _oruOut);
        }

        lastRedeemed[msg.sender] = block.number;

        ousd.burn(msg.sender, _ousdToRedeem);
        ousd.safeTransferFrom(
            msg.sender,
            address(profitController),
            _ousdFee
        );

        emit LogRedeem(_ousdIn, _collatOut, _oruOut, _ousdFee);
    }

    function collect() external onlyNonContract nonReentrant {
        require(
            lastRedeemed[msg.sender] + 1 <= block.number,
            "Bank: collect too soon"
        );

        uint256 _collatOut = redeemCollatBal[msg.sender];
        uint256 _oruOut = redeemOruBal[msg.sender];

        if (_collatOut > 0) {
            redeemCollatBal[msg.sender] = 0;
            unclaimedCollat -= _collatOut;
            safe.transferCollatTo(msg.sender, _collatOut);
        }

        if (_oruOut > 0) {
            redeemOruBal[msg.sender] = 0;
            unclaimedOru -= _oruOut;
            safe.transferOruTo(msg.sender, _oruOut);
        }
    }

    function arbMint(uint256 _collatIn) external override nonReentrant onlyArb {
        require(!zapMintPaused, "Bank: zap mint paused");
        require(_collatIn > 0, "Bank: _collatIn <= 0");

        // Don't take in more collateral than the pool ceiling for this token allows
        require(
            (safe.globalCollateralBalance() + _collatIn) <= poolCeiling,
            "Bank: Pool Ceiling"
        );

        uint256 _collatPrice = oracle.collatPrice();
        uint256 _collatToMintE18 = _collatIn * MISSING_PRECISION;

        uint256 _oruPrice = oracle.oruPrice();
        uint256 _collatToBuy = 0;
        if (tcr < TCR_MAX) {
            _collatToBuy = _collatAmtToBuyShare(
                _collatIn,
                _collatPrice,
                _oruPrice
            );
            _collatToMintE18 -= (_collatToBuy * MISSING_PRECISION);
        }

        collat.safeTransferFrom(msg.sender, address(this), _collatIn);
        uint256 _lpAmount = 0;
        if (_collatToBuy > 0) {
            collat.safeApprove(address(swapController), 0);
            collat.safeApprove(address(swapController), _collatToBuy);

            uint256 _minOruAmt = (_collatToBuy *
                PRICE_PRECISION *
                (RATIO_PRECISION - zapSlippage)) /
                _oruPrice /
                RATIO_PRECISION /
                2;

            _lpAmount = swapController.zapInUsdc(_collatToBuy, _minOruAmt, 0);

            _collatToMintE18 = (_collatToMintE18 * RATIO_PRECISION) / tcr;
            emit ZapSwapped(_collatToBuy, _lpAmount);
        }

        uint256 _ousdOut = (_collatToMintE18 * _collatPrice) / PRICE_PRECISION;

        if (_lpAmount > 0) {
            // transfer all lp token to Dustbin
            IERC20 lpToken = IERC20(address(oruPair));
            lpToken.safeTransfer(dustbin, lpToken.balanceOf(address(this)));
        }
        collat.safeTransfer(address(safe), collat.balanceOf(address(this)));
        ousd.mintByBank(msg.sender, _ousdOut);
    }

    function arbRedeem(uint256 _ousdIn)
        external
        override
        nonReentrant
        onlyArb
    {
        require(!redeemPaused, "Bank: redeem paused");
        require(_ousdIn > 0, "Bank: ousd <= 0");

        uint256 _oruOut = 0;
        uint256 _collatOut = (_ousdIn * PRICE_PRECISION) /
            oracle.collatPrice() /
            MISSING_PRECISION;

        if (ecr < ECR_MAX) {
            uint256 _oruOutValue = _ousdIn -
                ((_ousdIn * ecr) / RATIO_PRECISION);
            _oruOut = (_oruOutValue * PRICE_PRECISION) / oracle.oruPrice();
            _collatOut = (_collatOut * ecr) / RATIO_PRECISION;
        }

        require(
            _collatOut <= totalCollatAmt(),
            "Bank: insufficient bank balance"
        );

        if (_collatOut > 0) {
            safe.transferCollatTo(msg.sender, _collatOut);
        }

        if (_oruOut > 0) {
            oru.mintByBank(msg.sender, _oruOut);
        }

        ousd.burn(msg.sender, _ousdIn);
    }

    // When the protocol is recollateralizing, we need to give a discount of ORU to hit the new CR target
    // Thus, if the target collateral ratio is higher than the actual value of collateral, minters get ORU for adding collateral
    // This function simply rewards anyone that sends collateral to a pool with the same amount of ORU + the bonus rate
    // Anyone can call this function to recollateralize the protocol and take the extra ORU value from the bonus rate as an arb opportunity
    function recollateralize(uint256 _collatIn, uint256 _oruOutMin)
        external
        nonReentrant
        returns (uint256)
    {
        require(recollatPaused == false, "Bank: Recollat paused");

        // Don't take in more collateral than the pool ceiling for this token allows
        require(
            (safe.globalCollateralBalance() + _collatIn) <= poolCeiling,
            "Bank: Pool Ceiling"
        );

        uint256 _collatInE18 = _collatIn * MISSING_PRECISION;
        uint256 _oruPrice = oracle.oruPrice();
        uint256 _collatPrice = oracle.collatPrice();

        // Get the amount of ORU actually available (accounts for throttling)
        uint256 _oruAvailable = recollatAvailable();

        // Calculated the attempted amount of ORU

        uint256 _oruOut = (_collatInE18 *
            _collatPrice *
            (RATIO_PRECISION + bonusRate)) /
            RATIO_PRECISION /
            _oruPrice;

        // Make sure there is ORU available
        require(_oruOut <= _oruAvailable, "Bank: Insuf ORU Avail For RCT");

        // Check slippage
        require(_oruOut >= _oruOutMin, "Bank: ORU slippage");

        // Take in the collateral and pay out the ORU
        collat.safeTransferFrom(msg.sender, address(safe), _collatIn);
        oru.mintByBank(msg.sender, _oruOut);

        // Increment the outbound ORU, in E18
        // Used for recollat throttling
        rctHourlyCum[_curEpochHr()] += _oruOut;

        emit Recollateralized(_collatIn, _oruOut);
        return _oruOut;
    }

    function recollatTheoAvailableE18() public view returns (uint256) {
        uint256 _ousdTotalSupply = ousd.totalSupply();
        uint256 _desiredCollatE24 = tcr * _ousdTotalSupply;  // tcr 1 * 100
        uint256 _effectiveCollatE24 = calcEcr() * _ousdTotalSupply; //

        // Return 0 if already overcollateralized
        // Otherwise, return the deficiency
        if (_effectiveCollatE24 >= _desiredCollatE24) return 0;
        else {
            return (_desiredCollatE24 - _effectiveCollatE24) / RATIO_PRECISION;
        }
    }

    function recollatAvailable() public view returns (uint256) {
        uint256 _oruPrice = oracle.oruPrice();

        // Get the amount of collateral theoretically available
        uint256 _recollatTheoAvailableE18 = recollatTheoAvailableE18();

        // Get the amount of ORU theoretically outputtable
        uint256 _oruTheoOut = (_recollatTheoAvailableE18 * PRICE_PRECISION) /
            _oruPrice;

        // See how much ORU has been issued this hour
        uint256 _currentHourlyRct = rctHourlyCum[_curEpochHr()];

        // Account for the throttling
        return _comboCalcBbkRct(_currentHourlyRct, rctMaxPerHour, _oruTheoOut);
    }

    // Internal functions

    // Returns the current epoch hour
    function _curEpochHr() internal view returns (uint256) {
        return (block.timestamp / 3600); // Truncation desired
    }

    function _comboCalcBbkRct(
        uint256 _cur,
        uint256 _max,
        uint256 _theo
    ) internal pure returns (uint256) {
        if (_max == 0) {
            // If the hourly limit is 0, it means there is no limit
            return _theo;
        } else if (_cur >= _max) {
            // If the hourly limit has already been reached, return 0;
            return 0;
        } else {
            // Get the available amount
            uint256 _available = _max - _cur;

            if (_theo >= _available) {
                // If the the theoretical is more than the available, return the available
                return _available;
            } else {
                // Otherwise, return the theoretical amount
                return _theo;
            }
        }
    }

    function _collatAmtToBuyShare(
        uint256 _collatAmt,
        uint256 _collatPrice,
        uint256 _oruPrice
    ) internal view returns (uint256) {
        uint256 _r0 = 0;
        uint256 _r1 = 0;

        if (address(oru) <= address(collat)) {
            (_r1, _r0, ) = oruPair.getReserves(); // r1 = USDC, r0 = ORU
        } else {
            (_r0, _r1, ) = oruPair.getReserves(); // r0 = USDC, r1 = ORU
        }

        uint256 _rSwapFee = RATIO_PRECISION - swapFee;

        uint256 _k = ((RATIO_PRECISION * RATIO_PRECISION) / tcr) -
            RATIO_PRECISION;
        uint256 _b = _r0 +
            ((_rSwapFee *
                _r1 *
                _oruPrice *
                RATIO_PRECISION *
                PRICE_PRECISION) /
                ORU_PRECISION /
                PRICE_PRECISION /
                _k /
                _collatPrice) -
            ((_collatAmt * _rSwapFee) / PRICE_PRECISION);

        uint256 _tmp = ((_b * _b) / PRICE_PRECISION) +
            ((4 * _rSwapFee * _collatAmt * _r0) /
                PRICE_PRECISION /
                PRICE_PRECISION);

        return
            ((Babylonian.sqrt(_tmp * PRICE_PRECISION) - _b) * RATIO_PRECISION) /
            (2 * _rSwapFee);
    }

    function mintOusdByProfit(uint256 _amount) external onlyOwnerOrOperator {
        require(_amount > 0, "Safe: Zero amount");
        require(ecr > tcr, "Safe: tcr >= ecr");

        uint256 _available = ((ousd.totalSupply() * (ecr - tcr))) / tcr;

        _available =
            _available -
            ((_available * safe.excessCollateralSafetyMargin()) /
                RATIO_PRECISION);

        uint256 _ammtToMint = Math.min(_available, _amount);

        ousd.mintByBank(address(profitController), _ammtToMint);
    }

    function info()
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (tcr, ecr, mintFee, redeemFee);
    }
}
