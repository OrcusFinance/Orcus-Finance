// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "../interfaces/IProfitController.sol";
import "../interfaces/IORUStake.sol";
import "../interfaces/IOUSDERC20.sol";
import "../common/OrcusProtocol.sol";
import "../common/EnableSwap.sol";

import "../interfaces/IUniswapV2Router.sol";
import "../interfaces/IFirebirdRouter.sol";

contract ProfitController is
    IProfitController,
    OrcusProtocol,
    Initializable,
    EnableSwap
{
    using SafeERC20 for IOrcusERC20;
    using SafeERC20 for IERC20;

    IOrcusERC20 public oru;
    IOrcusERC20 public ousd;
    IERC20 public wastr;
    IERC20 public usdc;
    IOruStake public oruStake;

    uint256 public burnRate;

    event LogConvert(
        uint256 oruFromFarm,
        uint256 usdcFromArb,
        uint256 oruFromArb,
        uint256 ousdFromFee,
        uint256 usdcFromFee,
        uint256 oruFromFee,
        uint256 wastrFromInvest,
        uint256 usdcFromInvest,
        uint256 oruFromInvest,
        uint256 totalOru
    );
    event LogDistributeStake(uint256 distributeAmount, uint256 burnAmount);
    event LogSetOruStake(address oruStake);
    event LogSetBurnRate(uint256 burnRate);


    // TODO: for test i make usdc and wastr changable from contstructor.
    // FIXME: fix this when production deploy will arive (maybe).
    function init(
        address _oru,
        address _ousd,
        address _oruStake,
        address _swapController,
        address _usdc,
        address _wastr
    ) external initializer onlyOwner {
        oru = IOrcusERC20(_oru);
        ousd = IOrcusERC20(_ousd);
        oruStake = IOruStake(_oruStake);

        wastr = IERC20(_wastr);
        usdc = IERC20(_usdc);

        setSwapController(_swapController);
        setBurnRate((RATIO_PRECISION * 20) / 100); // 20%
    }

    function convert() external onlyOwnerOrOperator nonReentrant {
        // InitialOru is the profit from Farm penalty
        uint256 _oruFromFarm = oru.balanceOf(address(this));

        // InitialUsdc is the profit from Arbitrager
        uint256 _usdcFromArb = usdc.balanceOf(address(this));
        if (_usdcFromArb > 0) {
            usdc.safeApprove(address(swapController), 0);
            usdc.safeApprove(address(swapController), _usdcFromArb);
            swapController.swapUsdcToOru(_usdcFromArb, 0);
        }
        uint256 _oruAfterArb = oru.balanceOf(address(this));
        uint256 _oruFromArb = _oruAfterArb - _oruFromFarm;

        // InitialoUSD is the profit from Bank fee
        uint256 _ousdFromFee = ousd.balanceOf(address(this));
        uint256 _usdcFromFee = 0;
        if (_ousdFromFee > 0) {
            ousd.safeApprove(address(swapController), 0);
            ousd.safeApprove(address(swapController), _ousdFromFee);
            swapController.swapOusdToUsdc(_ousdFromFee, 0);

            _usdcFromFee = usdc.balanceOf(address(this));
            usdc.safeApprove(address(swapController), 0);
            usdc.safeApprove(address(swapController), _usdcFromFee);
            swapController.swapUsdcToOru(_usdcFromFee, 0);
        }
        uint256 _oruAfterFee = oru.balanceOf(address(this));
        uint256 _oruFromFee = _oruAfterFee - _oruAfterArb;

        // InitialWastr is the profit from Invest
        uint256 _astrFromInvest = wastr.balanceOf(address(this));
        uint256 _usdcFromInvest = 0;
        if (_astrFromInvest > 0) {
            wastr.safeApprove(address(swapController), 0);
            wastr.safeApprove(address(swapController), _astrFromInvest);
            swapController.swapWAstrToUsdc(_astrFromInvest, 0);

            _usdcFromInvest = usdc.balanceOf(address(this));
            usdc.safeApprove(address(swapController), 0);
            usdc.safeApprove(address(swapController), _usdcFromInvest);
            swapController.swapUsdcToOru(_usdcFromInvest, 0);
        }
        uint256 _oruAfterInvest = oru.balanceOf(address(this));
        uint256 _oruFromInvest = _oruAfterInvest - _oruAfterFee;

        emit LogConvert(
            _oruFromFarm,
            _usdcFromArb,
            _oruFromArb,
            _ousdFromFee,
            _usdcFromFee,
            _oruFromFee,
            _astrFromInvest,
            _usdcFromInvest,
            _oruFromInvest,
            _oruAfterInvest
        );
    }

    function distributeStake(uint256 _amount)
        external
        override
        onlyOwnerOrOperator
    {
        require(_amount > 0, "Amount must be greater than 0");

        uint256 _actualAmt = Math.min(oru.balanceOf(address(this)), _amount);
        uint256 _amtToBurn = (_actualAmt * burnRate) / RATIO_PRECISION;

        uint256 _distributeAmt = _actualAmt - _amtToBurn;
        if (_amtToBurn > 0) {
            oru.burn(address(this), _amtToBurn);
        }

        oru.safeApprove(address(oruStake), 0);
        oru.safeApprove(address(oruStake), _distributeAmt);
        oruStake.distribute(_distributeAmt);

        emit LogDistributeStake(_distributeAmt, _amtToBurn);
    }

    function setOruStake(address _oruStake) public onlyOwner {
        require(_oruStake != address(0), "Invalid address");
        oruStake = IOruStake(_oruStake);
        emit LogSetOruStake(_oruStake);
    }

    function setBurnRate(uint256 _burnRate) public onlyOwnerOrOperator {
        burnRate = _burnRate;
        emit LogSetBurnRate(burnRate);
    }

    function transferTo(
        address _receiver,
        address _token,
        uint256 _amount
    ) public onlyOwner {
        IERC20 token = IERC20(_token);
        require(
            token.balanceOf(address(this)) >= _amount,
            "Not enough balance"
        );
        require(_amount > 0, "Zero amount");
        token.safeTransfer(_receiver, _amount);
    }

    function rescueFund(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(owner(), _amount);
    }
}
