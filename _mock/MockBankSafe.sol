pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IOUSDERC20.sol";

contract MockBankSafe {

    using SafeERC20 for IERC20;
    using SafeERC20 for IOrcusERC20;

    IERC20 public collat;
    IOrcusERC20 public oru;

    uint256 public investingAmt = 0;

    constructor(address _collat, address _oru) {
        collat = IERC20(_collat);
        oru = IOrcusERC20(_oru);
    }

    function globalCollateralBalance() public returns(uint256) {

        uint256 bal = collat.balanceOf(address(this));
        return bal;
    }

    function transferCollatTo(address _to, uint256 _amount) public {
        collat.safeTransfer(_to, _amount);
    }

    function transferOruTo(address _to, uint256 _amount) public {
        oru.safeTransfer(_to, _amount);
    }

    function fakeBurnCollatToDecreaseECR(uint256 _amtToFakeBurn) public {

        collat.safeTransfer(0x000000000000000000000000000000000000dEaD, _amtToFakeBurn);

    }

}
