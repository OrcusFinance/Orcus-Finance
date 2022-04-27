// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "../common/OrcusProtocol.sol";
import "../common/EnableSwap.sol";
import "../common/Farmable.sol";
import "../interfaces/IOUSDERC20.sol";
import "../interfaces/IFarm.sol";

contract Dustbin is OrcusProtocol, EnableSwap, Farmable {
    IOrcusERC20 public oru;
    IUniswapV2Pair public oruPair;

    event LogSetOru(address oru, address oruPair);
    event LogBurn(uint256 lpAmount, uint256 oruBurnt);

    constructor(
        address _oruPair,
        address _oru,
        address _swapController
    ) {
        setOru(_oru, _oruPair);
        setSwapController(_swapController);
    }

    function burnLp(uint256 _amount) external onlyOwnerOrOperator {
        uint256 _lpBalance = oruPair.balanceOf(address(this));
        require(_lpBalance >= _amount, "Dustbin: amount > balance");

        require(
            oruPair.approve(address(swapController), 0),
            "Dustbin: failed to approve"
        );
        require(
            oruPair.approve(address(swapController), _lpBalance),
            "Dustbin: failed to approve"
        );

        uint256 _oruAmount = swapController.zapOutOru(_amount, 0);

        oru.burn(address(this), _oruAmount);

        emit LogBurn(_amount, _oruAmount);
    }

    function setOru(address _oru, address _oruPair) public onlyOwner {
        require(
            _oru != address(0) && _oruPair != address(0),
            "Dustbin: invalid oru address"
        );
        oru = IOrcusERC20(_oru);
        oruPair = IUniswapV2Pair(_oruPair);
        emit LogSetOru(_oru, _oruPair);
    }
}
