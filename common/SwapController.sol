// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/ISwapController.sol";
import "../interfaces/IUniswapV2Router.sol";
import "./OrcusProtocol.sol";
import "../libraries/TransferHelper.sol";


interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
    function balanceOf(address account) external view returns (uint256);
}

library Babylonian {
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
        // else z = 0
    }
}

library SafeMath {
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, 'ds-math-add-overflow');
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, 'ds-math-sub-underflow');
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, 'ds-math-mul-overflow');
    }
    function div(uint a, uint b) internal pure returns (uint c) {
        require(b > 0, 'ds-math-division-by-zero');
        c = a / b;
    }
}

contract SwapController is ISwapController, OrcusProtocol {
    using SafeERC20 for IERC20;
    using SafeMath for uint;

    uint256 private constant TIMEOUT = 300;

    IUniswapV2Router public fbRouter;
    IUniswapV2Factory public fbFactory;
    IUniswapV2Pair public fbOruPair;
    IUniswapV2Pair public fbOusdPair;

    address public WBNB;  // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!


    uint public maxResidual = 100; // 1%, set 10000 to disable

    IERC20 public oru;
    IERC20 public ousd;
    IERC20 public usdc;
    IERC20 public wastr;

    address[] public fbOruPairPath;
    address[] public fbOusdPairPath;
    address[] public fbWAstrPairPath;

    address[] public fbUsdcOruPairPath;
    address[] public fbUsdcOusdPairPath;
    address[] public fbUsdcWAstrPairPath;

    uint8[] private fbDexIdsFB;
    uint8[] private fbDexIdsQuick;

    event LogSetContracts(
        address fbRouter,
        address fbFactory,
        address fbOruPair,
        address fbOusdPair
    );
    event LogSetPairPaths(
        address[] fbOruPairPath,
        address[] fbOusdPairPath,
        address[] fbWAstrPairPath
    );
    event LogSetDexIds(uint8[] fbDexIdsFB, uint8[] fbDexIdsQuick);

    constructor(
        address _router,
        address _factory,
        address _OruPair,
        address _OusdPair,
    //address _WAstrPair, // 0x6e7a5FAFcec6BB1e78bAE2A1F0B612012BF14827
        address _oru,
        address _ousd,
        address _usdc, // 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174
        address _wastr // 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270
    ) {
        require(
            _router != address(0) &&
            _factory != address(0) &&
            _OruPair != address(0) &&
            _OusdPair != address(0),
            "Swap: Invalid Address"
        );

        setContracts( _router, _factory, _OruPair, _OusdPair);

        address[] memory _OruPairPath = new address[](2);
        _OruPairPath[0] = _oru;
        _OruPairPath[1] = _usdc;
        address[] memory _OusdPairPath = new address[](2);
        _OusdPairPath[0] = _ousd;
        _OusdPairPath[1] = _usdc;
        address[] memory _WAstrPairPath = new address[](2);
        _WAstrPairPath[0] = _wastr;
        _WAstrPairPath[1] = _usdc;
        setPairPaths(_OruPairPath, _OusdPairPath, _WAstrPairPath);

        fbUsdcOruPairPath = [_usdc, _oru];
        fbUsdcOusdPairPath = [_usdc, _ousd];
        fbUsdcWAstrPairPath = [_usdc, _wastr];

        uint8[] memory _fbDexIdsFB = new uint8[](1);
        _fbDexIdsFB[0] = 0;
        uint8[] memory _fbDexIdsQuick = new uint8[](1);
        _fbDexIdsQuick[0] = 1;
        setDexIds(_fbDexIdsFB, _fbDexIdsQuick);

        oru = IERC20(_oru);
        ousd = IERC20(_ousd);
        usdc = IERC20(_usdc);
        wastr = IERC20(_wastr);

        WBNB = _wastr;
    }

    // Swap functions
    function swapUsdcToOusd(uint256 _amount, uint256 _minOut)
    external
    override
    nonReentrant
    {

        usdc.safeTransferFrom(msg.sender, address(this), _amount);
        usdc.safeApprove(address(fbRouter), 0);
        usdc.safeApprove(address(fbRouter), _amount);

        uint balancethis = usdc.balanceOf(address(this));
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = fbOusdPair.getReserves();

        fbRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amount,
            _minOut,
            fbUsdcOusdPairPath,
            msg.sender,
            block.timestamp + TIMEOUT
        );
    }

    function swapUsdcToOru(uint256 _amount, uint256 _minOut)
    external
    override
    nonReentrant
    {
        usdc.safeTransferFrom(msg.sender, address(this), _amount);
        usdc.safeApprove(address(fbRouter), 0);
        usdc.safeApprove(address(fbRouter), _amount);

        fbRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amount,
            _minOut,
            fbUsdcOruPairPath,
            msg.sender,
            block.timestamp + TIMEOUT
        );
    }

    function swapOruToUsdc(uint256 _amount, uint256 _minOut)
    external
    override
    nonReentrant
    {
        oru.safeTransferFrom(msg.sender, address(this), _amount);
        oru.safeApprove(address(fbRouter), 0);
        oru.safeApprove(address(fbRouter), _amount);

        fbRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amount,
            _minOut,
            fbOruPairPath,
            msg.sender,
            block.timestamp + TIMEOUT
        );
    }

    function swapOusdToUsdc(uint256 _amount, uint256 _minOut)
    external
    override
    nonReentrant
    {
        ousd.safeTransferFrom(msg.sender, address(this), _amount);
        ousd.safeApprove(address(fbRouter), 0);
        ousd.safeApprove(address(fbRouter), _amount);

        fbRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amount,
            _minOut,
            fbOusdPairPath,
            msg.sender,
            block.timestamp + TIMEOUT
        );
    }

    function swapWAstrToUsdc(uint256 _amount, uint256 _minOut)
    external
    override
    nonReentrant
    {
        wastr.safeTransferFrom(msg.sender, address(this), _amount);
        wastr.safeApprove(address(fbRouter), 0);
        wastr.safeApprove(address(fbRouter), _amount);

        fbRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amount,
            _minOut,
            fbWAstrPairPath,
            msg.sender,
            block.timestamp + TIMEOUT
        );
    }

    function zapInOru(
        uint256 _amount,
        uint256 _minUsdc,
        uint256 _minLp
    ) external override nonReentrant returns (uint256) {


        oru.safeTransferFrom(msg.sender, address(this), _amount);

        uint256[] memory _amounts = new uint256[](3);
        _amounts[0] = _amount; // amount_from (ORU)
        _amounts[1] = _minUsdc; // minTokenB (USDC)
        _amounts[2] = _minLp; // minLp

        uint256 _lpAmount = _zapInToken(
            address(oru),
            _amounts,
            address(fbOruPair),
            true
        );



        require(_lpAmount > 0, "Swap: No lp");
        require(
            fbOruPair.transfer(msg.sender, _lpAmount),
            "Swap: Faild to transfer"
        );

        return _lpAmount;
    }

    function zapInUsdc(
        uint256 _amount,
        uint256 _minOru,
        uint256 _minLp
    ) external override nonReentrant returns (uint256) {
        usdc.safeTransferFrom(msg.sender, address(this), _amount);

        uint256[] memory _amounts = new uint256[](3);
        _amounts[0] = _amount; // amount_from (USDC)
        _amounts[1] = _minOru; // minTokenB (ORU)
        _amounts[2] = _minLp; // minLp

        uint256 _lpAmount = _zapInToken(
            address(usdc),
            _amounts,
            address(fbOruPair),
            true
        );

        require(_lpAmount > 0, "Swap: No lp");
        require(
            fbOruPair.transfer(msg.sender, _lpAmount),
            "Swap: Faild to transfer"
        );

        return _lpAmount;
    }

    function zapOutOru(uint256 _amount, uint256 _minOut)
    external
    override
    nonReentrant
    returns (uint256)
    {
        require(
            fbOruPair.transferFrom(msg.sender, address(this), _amount),
            "Swap: Failed to transfer pair"
        );


        uint256 _oruAmount = _zapOut(
            address(fbOruPair),
            _amount,
            address(oru),
            _minOut
        );



        require(_oruAmount > 0, "Swap: Oru amount is 0");
        oru.safeTransfer(msg.sender, _oruAmount);
        return _oruAmount;
    }

    // Setters
    function setContracts(
        address _router,
        address _factory,
        address _OruPair,
        address _OusdPair
    ) public onlyOwner {

        if (_router != address(0)) {
            fbRouter = IUniswapV2Router(_router);
        }
        if (_factory != address(0)) {
            fbFactory = IUniswapV2Factory(_factory);
        }
        if (_OruPair != address(0)) {
            fbOruPair = IUniswapV2Pair(_OruPair);
        }
        if (_OusdPair != address(0)) {
            fbOusdPair = IUniswapV2Pair(_OusdPair);
        }

        emit LogSetContracts(
            _router,
            _factory,
            _OruPair,
            _OusdPair
        );
    }

    function setPairPaths(
        address[] memory _OruPairPath,
        address[] memory _OusdPairPath,
        address[] memory _WAstrPairPath
    ) public onlyOwner {
        fbOruPairPath = _OruPairPath;
        fbOusdPairPath = _OusdPairPath;
        fbWAstrPairPath = _WAstrPairPath;

        emit LogSetPairPaths(fbOruPairPath, fbOusdPairPath, fbWAstrPairPath);
    }

    function setDexIds(
        uint8[] memory _fbDexIdsFB,
        uint8[] memory _fbDexIdsQuick
    ) public onlyOwner {
        fbDexIdsFB = _fbDexIdsFB;
        fbDexIdsQuick = _fbDexIdsQuick;

        emit LogSetDexIds(fbDexIdsFB, fbDexIdsQuick);
    }

    function _zapInToken(address _from, uint[] memory amounts, address _to, bool transferResidual) private returns (uint256 lpAmt) {
        _approveTokenIfNeeded(_from);

        if (_from == IUniswapV2Pair(_to).token0() || _from == IUniswapV2Pair(_to).token1()) {
            // swap half amount for other
            address other;
            uint256 sellAmount;
            {
                address token0 = IUniswapV2Pair(_to).token0();
                address token1 = IUniswapV2Pair(_to).token1();
                other = _from == token0 ? token1 : token0;
                sellAmount = calculateSwapInAmount(_to, _from, amounts[0], token0);
            }
            uint otherAmount = _swap(_from, sellAmount, other, address(this), _to);
            require(otherAmount >= amounts[1], "Zap: Insufficient Receive Amount");


            lpAmt = _pairDeposit(_to, _from, other, amounts[0].sub(sellAmount), otherAmount, address(this), false, transferResidual);

        } else {
            uint bnbAmount = _swapTokenForBNB(_from, amounts[0], address(this), address(0));
            lpAmt = _swapBNBToLp(IUniswapV2Pair(_to), bnbAmount, address(this), 0, transferResidual);
        }

        require(lpAmt >= amounts[2], "Zap: High Slippage In");
        return lpAmt;
    }

    function _zapOut (address _from, uint amount, address _toToken, uint256 _minTokensRec) private returns (uint256) {
        _approveTokenIfNeeded(_from);

        address token0;
        address token1;
        uint256 amountA;
        uint256 amountB;
        {
            IUniswapV2Pair pair = IUniswapV2Pair(_from);
            token0 = pair.token0();
            token1 = pair.token1();
            (amountA, amountB) = fbRouter.removeLiquidity(token0, token1, amount, 0, 0, address(this), block.timestamp);
        }

        uint256 tokenBought;
        _approveTokenIfNeeded(token0);
        _approveTokenIfNeeded(token1);
        if (_toToken == WBNB) {
            address _lpOfFromAndTo = WBNB == token0 || WBNB == token1 ? _from : address(0);
            tokenBought = _swapTokenForBNB(token0, amountA, address(this), _lpOfFromAndTo);
            tokenBought = tokenBought + (_swapTokenForBNB(token1, amountB, address(this), _lpOfFromAndTo));
        } else {
            address _lpOfFromAndTo = _toToken == token0 || _toToken == token1 ? _from : address(0);
            tokenBought = _swap(token0, amountA, _toToken, address(this), _lpOfFromAndTo);
            tokenBought = tokenBought + (_swap(token1, amountB, _toToken, address(this), _lpOfFromAndTo));

        }





        require(tokenBought >= _minTokensRec, "Zap: High Slippage Out");
        if (_toToken == WBNB) {
            TransferHelper.safeTransferETH(address(this), tokenBought);
        } else {
            IERC20(_toToken).safeTransfer(address(this), tokenBought);
        }

        return tokenBought;
    }

    function _approveTokenIfNeeded(address token) private {
        if (IERC20(token).allowance(address(this), address(fbRouter)) == 0) {
            IERC20(token).safeApprove(address(fbRouter), 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        }
    }


    function _swapTokenForBNB(address token, uint amount, address _receiver, address lpTokenBNB) private returns (uint) {
        if (token == WBNB) {
            _transferToken(WBNB, _receiver, amount);
            return amount;
        }

        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = WBNB;
        uint[] memory amounts;
        if (path.length > 0) {
            amounts = fbRouter.swapExactTokensForETH(amount, 1, path, _receiver, block.timestamp);
        } else if (lpTokenBNB != address(0)) {
            path = new address[](1);
            path[0] = lpTokenBNB;
            amounts = fbRouter.swapExactTokensForETH(amount, 1, path, _receiver, block.timestamp);
        } else {
            revert("FireBirdZap: !path TokenBNB");
        }

        return amounts[amounts.length - 1];
    }

    function _swap(address _from, uint _amount, address _to, address _receiver, address _lpOfFromTo) internal returns (uint) {
        if (_from == _to) {
            if (_receiver != address(this)) {
                IERC20(_from).safeTransfer(_receiver, _amount);
            }
            return _amount;
        }
        address[] memory path = new address[](2);
        path[0] = _from;
        path[1] = _to;
        uint[] memory amounts;
        if (path.length > 0) {// use fireBird
            amounts = fbRouter.swapExactTokensForTokens(_amount, 1, path, _receiver, block.timestamp);
        } else if (_lpOfFromTo != address(0)) {
            path = new address[](1);
            path[0] = _lpOfFromTo;
            amounts = fbRouter.swapExactTokensForTokens(_amount, 1, path, _receiver, block.timestamp);
        } else {
            revert("FireBirdZap: !path swap");
        }

        return amounts[amounts.length - 1];
    }

    function _transferToken(address token, address to, uint amount) internal {
        if (amount == 0) {
            return;
        }

        if (token == WBNB) {
            IWETH(WBNB).withdraw(amount);
            if (to != address(this)) {
                TransferHelper.safeTransferETH(to, amount);
            }
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
        return;
    }

    function calculateSwapInAmount(address pair, address tokenIn, uint256 userIn, address pairToken0) internal view returns (uint256) {
        (uint32 tokenWeight0, uint32 tokenWeight1) = (50,50); // ????????????????????????????
        uint swapFee = 0; // ?????????????????????
        if (tokenWeight0 == 50) {
            (uint256 res0, uint256 res1,) = IUniswapV2Pair(pair).getReserves();
            uint reserveIn = tokenIn == pairToken0 ? res0 : res1;
            uint256 rMul = uint256(10000).sub(uint256(swapFee));

            return _getExactSwapInAmount(reserveIn, userIn, rMul);
        } else {
            uint256 otherWeight = tokenIn == pairToken0 ? uint256(tokenWeight1) : uint256(tokenWeight0);
            return userIn.mul(otherWeight).div(100);
        }
    }

    function _getExactSwapInAmount(
        uint256 reserveIn,
        uint256 userIn,
        uint256 rMul
    ) internal pure returns (uint256) {
        return Babylonian.sqrt(reserveIn.mul(userIn.mul(40000).mul(rMul) + reserveIn.mul(rMul.add(10000)).mul(rMul.add(10000)))).sub(reserveIn.mul(rMul.add(10000))) / (rMul.mul(2));
    }

    function _pairDeposit(
        address _pair,
        address _poolToken0,
        address _poolToken1,
        uint256 token0Bought,
        uint256 token1Bought,
        address receiver,
        bool isfireBirdPair,
        bool transferResidual
    ) internal returns (uint256 lpAmt) {
        _approveTokenIfNeeded(_poolToken0);
        _approveTokenIfNeeded(_poolToken1);

        uint256 amountA;
        uint256 amountB;
        (amountA, amountB, lpAmt) = fbRouter.addLiquidity(_poolToken0, _poolToken1, token0Bought, token1Bought, 1, 1, receiver, block.timestamp);

        uint amountAResidual = token0Bought.sub(amountA);
        if (transferResidual || amountAResidual > token0Bought.mul(maxResidual).div(10000)) {
            if (amountAResidual > 0) {
                //Returning Residue in token0, if any.
                _transferToken(_poolToken0, msg.sender, amountAResidual);
            }
        }

        uint amountBRedisual = token1Bought.sub(amountB);
        if (transferResidual || amountBRedisual > token1Bought.mul(maxResidual).div(10000)) {
            if (amountBRedisual > 0) {
                //Returning Residue in token1, if any
                _transferToken(_poolToken1, msg.sender, amountBRedisual);
            }
        }

        return lpAmt;
    }

    function _swapBNBToLp(IUniswapV2Pair pair, uint amount, address receiver, uint _minTokenB, bool transferResidual) private returns (uint256 lpAmt) {
        address lp = address(pair);

        // Lp
        if (pair.token0() == WBNB || pair.token1() == WBNB) {
            address token = pair.token0() == WBNB ? pair.token1() : pair.token0();
            uint swapValue = calculateSwapInAmount(lp, WBNB, amount, pair.token0());
            uint tokenAmount = _swapBNBForToken(token, swapValue, address(this), lp);
            require(tokenAmount >= _minTokenB, "Zap: Insufficient Receive Amount");

            uint256 wbnbAmount = amount.sub(swapValue);
            IWETH(WBNB).deposit{value : wbnbAmount}();
            lpAmt = _pairDeposit(lp, WBNB, token, wbnbAmount, tokenAmount, receiver, false, transferResidual);
        } else {
            address token0 = pair.token0();
            address token1 = pair.token1();
            uint token0Amount;
            uint token1Amount;
            {
                uint32 tokenWeight0 = 50; // ??????????????????????
                uint swap0Value = amount.mul(uint(tokenWeight0)).div(100);
                token0Amount = _swapBNBForToken(token0, swap0Value, address(this), address(0));
                token1Amount = _swapBNBForToken(token1, amount.sub(swap0Value), address(this), address(0));
            }

            lpAmt = _pairDeposit(lp, token0, token1, token0Amount, token1Amount, receiver, false, transferResidual);
        }
    }

    function _swapBNBForToken(address token, uint value, address _receiver, address lpBNBToken) private returns (uint) {
        if (token == WBNB) {
            IWETH(WBNB).deposit{value : value}();
            if (_receiver != address(this)) {
                IERC20(WBNB).safeTransfer(_receiver, value);
            }
            return value;
        }
        address[] memory path = new address[](2);
        path[0] = WBNB;
        path[1] = token;
        uint[] memory amounts;
        if (path.length > 0) {
            amounts = fbRouter.swapExactETHForTokens{value : value}(1, path, _receiver, block.timestamp);
        } else if (lpBNBToken != address(0)) {
            path = new address[](1);
            path[0] = lpBNBToken;
            amounts = fbRouter.swapExactETHForTokens{value : value}(1, path, _receiver, block.timestamp);
        } else {
            revert("FireBirdZap: !path BNBToken");
        }

        return amounts[amounts.length - 1];
    }

}