// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Callee.sol";
//import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3FlashCallback.sol";

import "../common/OrcusProtocol.sol";
import "../common/EnableSwap.sol";
import "../interfaces/IBank.sol";
import "../libraries/Babylonian.sol";

contract Arbitrager is OrcusProtocol, EnableSwap, IUniswapV2Callee {
    using SafeERC20 for IERC20;

    IBank public bank;
    IERC20 public collat;
    IERC20 public ousd;
    IERC20 public oru;
    address public profitController;
    IUniswapV2Pair public ousdPair;

    uint256 private swapFee;
    uint256 public repayFee = 4;

    uint256 private targetHighPrice;
    uint256 private targetLowPrice;

    struct FlashCallbackData {
        uint256 usdcAmt;
        bool isBuy;
    }

    event LogSetContracts(
        address bank,
        address collat,
        address ousd,
        address oru,
        address profitHandler,
        address ousdPair
    );
    event LogSetTargetBand(uint256 targetHighPrice, uint256 targetLowPrice);
    event LogSetSwapFee(uint256 swapFee);
    event LogTrade(
        uint256 initialUsdc,
        uint256 profit,
        bool indexed isBuy
    );

    constructor(
        address _bank,
        address _collat,
        address _ousd,
        address _oru,
        address _profitController,
        address _ousdPair,
        address _swapController
    ) {
        setContracts(
            _bank,
            _collat,
            _ousd,
            _oru,
            _profitController,
            _ousdPair
        );
        uint256 _highBand = (PRICE_PRECISION * 45) / 10000; // 0.45%
        uint256 _lowBand = (PRICE_PRECISION * 40) / 10000; // 0.4%
        setTargetBand(_lowBand, _highBand);
        setSwapFee((SWAP_FEE_PRECISION * 2) / 1000); // 0.2%

        setSwapController(_swapController);
    }

    function setContracts(
        address _bank,
        address _collat,
        address _ousd,
        address _oru,
        address _profitController,
        address _ousdPair
    ) public onlyOwner {
        bank = _bank != address(0) ? IBank(_bank) : bank;
        collat = _collat != address(0) ? IERC20(_collat) : collat;
        ousd = _ousd != address(0) ? IERC20(_ousd) : ousd;
        oru = _oru != address(0) ? IERC20(_oru) : oru;
        profitController = _profitController != address(0)
        ? _profitController
        : profitController;
        ousdPair = _ousdPair != address(0)
        ? IUniswapV2Pair(_ousdPair)
        : ousdPair;

        emit LogSetContracts(
            address(bank),
            address(collat),
            address(ousd),
            address(oru),
            profitController,
            address(ousdPair)
        );
    }

    function setTargetBand(uint256 _lowBand, uint256 _highBand)
    public
    onlyOwnerOrOperator
    {
        targetHighPrice = PRICE_PRECISION + _highBand;
        targetLowPrice = PRICE_PRECISION - _lowBand;
        emit LogSetTargetBand(targetHighPrice, targetLowPrice);
    }

    function setSwapFee(uint256 _swapFee) public onlyOwnerOrOperator {
        swapFee = _swapFee;
        emit LogSetSwapFee(swapFee);
    }

    function setRepayFee(uint256 _fee) public onlyOwnerOrOperator {
        repayFee = _fee;
    }


    function uniswapV2Call(address , uint , uint , bytes calldata data) external override {
        require(
            msg.sender == address(ousdPair),
            "Arbitrager: sender not pool"
        );


        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = ousdPair.getReserves();


        FlashCallbackData memory decoded = abi.decode(
            data,
            (FlashCallbackData)
        );

        if (decoded.isBuy) {
            // Buy oUSD
            _buyOusd(decoded.usdcAmt);
        } else {
            // Sell oUSD
            _sellOusd(decoded.usdcAmt);
        }

        // Assert profit
        uint256 fee = decoded.usdcAmt * repayFee / 1000;
        uint256 _usdcOwed = decoded.usdcAmt + fee;
        uint256 _balanceAfter = collat.balanceOf(address(this));
        require(_balanceAfter > _usdcOwed, "Arbitrager: Minus profit");

        uint256 _profit = _balanceAfter - _usdcOwed;

        // Repay
        collat.safeTransfer(address(ousdPair), _usdcOwed);

        // Send profit to Profit Handler
        collat.safeTransfer(profitController, _profit);

        emit LogTrade(decoded.usdcAmt, _profit, decoded.isBuy);
    }

    function buyOusd() external onlyOwnerOrOperator {
        uint256 _rsvOusd = 0;
        uint256 _rsvUsdc = 0;
        if (address(ousd) <= address(collat)) {
            (_rsvOusd, _rsvUsdc, ) = ousdPair.getReserves();
        } else {
            (_rsvUsdc, _rsvOusd, ) = ousdPair.getReserves();
        }

        uint256 _usdcAmt = _calcUsdcAmtToBuy(_rsvUsdc, _rsvOusd);

        _usdcAmt =
        (_usdcAmt * SWAP_FEE_PRECISION) /
        (SWAP_FEE_PRECISION - swapFee);


        ousdPair.swap(
            0,
            _usdcAmt,
            address(this),
            abi.encode(FlashCallbackData({usdcAmt: _usdcAmt, isBuy: true}))
        );
    }

    function _buyOusd(uint256 _usdcAmt) internal {

        // buy oUSD
        collat.safeApprove(address(swapController), 0);
        collat.safeApprove(address(swapController), _usdcAmt);

        swapController.swapUsdcToOusd(_usdcAmt, 0);

        // redeem oUSD
        uint256 _ousdAmount = ousd.balanceOf(address(this));
        ousd.safeApprove(address(bank), 0);
        ousd.safeApprove(address(bank), _ousdAmount);
        bank.arbRedeem(_ousdAmount);

        // sell ORU
        uint256 _oruAmount = oru.balanceOf(address(this));
        if (_oruAmount > 0) {
            oru.safeApprove(address(swapController), 0);
            oru.safeApprove(address(swapController), _oruAmount);
            swapController.swapOruToUsdc(_oruAmount, 0);
        }
    }

    function _calcUsdcAmtToBuy(uint256 _rsvUsdc, uint256 _rsvOusd)
    internal
    view
    returns (uint256)
    {
        // Buying oUSD means we want to increase the oUSD price to targetLowPrice
        uint256 _y = ((targetLowPrice * _rsvUsdc * _rsvOusd) /
        OUSD_PRECISION);

        return Babylonian.sqrt(_y) - _rsvUsdc;
    }

    function sellOusd() external onlyOwnerOrOperator {
        uint256 _rsvOusd = 0;
        uint256 _rsvUsdc = 0;
        if (address(ousd) <= address(collat)) {
            (_rsvOusd, _rsvUsdc, ) = ousdPair.getReserves();
        } else {
            (_rsvUsdc, _rsvOusd, ) = ousdPair.getReserves();
        }

        uint256 _ousdAmt = _calcOusdAmtToSell(_rsvUsdc, _rsvOusd);
        uint256 _usdcAmt = (_ousdAmt * SWAP_FEE_PRECISION) /
        (SWAP_FEE_PRECISION - swapFee) /
        MISSING_PRECISION;

        ousdPair.swap(
            0,
            _usdcAmt,
            address(this),
            abi.encode(FlashCallbackData({usdcAmt: _usdcAmt, isBuy: true}))
        );
    }

    function _sellOusd(uint256 _usdcAmt) internal {
        // mint oUSD to sell
        collat.safeApprove(address(bank), 0);
        collat.safeApprove(address(bank), _usdcAmt);
        bank.arbMint(_usdcAmt);

        // sell oUSD for USDC
        uint256 _ousdAmt = ousd.balanceOf(address(this));
        ousd.safeApprove(address(swapController), 0);
        ousd.safeApprove(address(swapController), _ousdAmt);
        swapController.swapOusdToUsdc(_ousdAmt, 0);
    }

    function _calcOusdAmtToSell(uint256 _rsvUsdc, uint256 _rsvOusd)
    internal
    view
    returns (uint256)
    {
        // Selling oUSD means we want to decrease the oUSD price to targetHighPrice
        uint256 _y = ((_rsvOusd * _rsvUsdc * targetHighPrice) *
        OUSD_PRECISION) /
        PRICE_PRECISION /
        PRICE_PRECISION;

        uint256 _result = ((Babylonian.sqrt(_y) * PRICE_PRECISION) /
        targetHighPrice) - _rsvOusd;

        return _result;
    }
}