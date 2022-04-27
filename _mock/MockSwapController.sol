pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


// @dev
// Simple transfer from contract to test functionality of other contracts;
contract MockSwapController {

    using SafeERC20 for IERC20;

    IERC20 public oru;
    IERC20 public ousd;
    IERC20 public usdc;
    IERC20 public wastr;

    constructor(address _oru, address _usdc, address _ousd, address _wastr) {
        oru = IERC20(_oru);
        ousd = IERC20(_ousd);
        usdc = IERC20(_usdc);
        wastr = IERC20(_wastr);
    }

    // Main function that will return ORU
    function swapUsdcToOru(uint256 _amount, uint256 _minOut) external {
        uint returnedOruAmount = (_amount * 1e12);
        usdc.safeTransferFrom(msg.sender, address(this), _amount);
        oru.safeTransfer(msg.sender, returnedOruAmount);

    }

    function swapOusdToUsdc(uint256 _amount, uint256 _minOut) external {
        uint returnedOruAmount = (_amount / 1e12);

        ousd.safeTransferFrom(msg.sender, address(this), _amount);
        usdc.safeTransfer(msg.sender, returnedOruAmount);

    }

    function swapWAstrToUsdc(uint256 _amount, uint256 _minOut) external {
        uint returnedOruAmount = _amount * 3;

        wastr.safeTransferFrom(msg.sender, address(this), _amount);
        oru.safeTransfer(msg.sender, returnedOruAmount);

    }

    function zapInOru(uint256 _amount, uint256 _minUsdc, uint256 _minLp) external returns(uint256) {
        oru.safeTransferFrom(msg.sender, address(this), _amount);


        return 1;
    }

}
