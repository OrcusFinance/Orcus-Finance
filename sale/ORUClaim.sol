pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IOUSDERC20.sol";

contract ORUClaim is Ownable {

    using SafeERC20 for IOrcusERC20;
    using SafeERC20 for IERC20;

    IOrcusERC20 public oru;

    struct UserClaimInfo {
        uint256 oruAmt;
        uint256 lastClaimed;
        uint256 distributionAmt;
        bool firstTimeClaimed;
        bool userExist;
    }

    uint256 public constant INTERVAL_BETWEEN_CLAIMS = 14 days; // 1 minute change to 14 days when realese.

    mapping (address => UserClaimInfo) public claims;

    // Constructor
    constructor(address _oru) {
        oru = IOrcusERC20(_oru);
    }

    // Claim function
    function claim() external {
        require(claims[msg.sender].userExist, "User does not exist on claim list");
        require(claims[msg.sender].oruAmt > 0, "Claims is over for this user");

        uint256 claimTime = block.timestamp;
        uint amtToSend = claims[msg.sender].distributionAmt;

        if (!claims[msg.sender].firstTimeClaimed) {
            oru.safeTransfer(msg.sender, amtToSend);

            claims[msg.sender].lastClaimed = claimTime;
            claims[msg.sender].oruAmt -= amtToSend;
            claims[msg.sender].firstTimeClaimed = true;
        }

        else {
            require(claims[msg.sender].lastClaimed + INTERVAL_BETWEEN_CLAIMS <= claimTime, "Claim time isn't come");

            oru.safeTransfer(msg.sender, amtToSend);
            claims[msg.sender].lastClaimed = claimTime;
            claims[msg.sender].oruAmt -= amtToSend;
        }
    }

    function uploadClaimInfo(address[] memory recipients, uint256[] memory amounts) external onlyOwner {
        require(recipients.length == amounts.length, "incorrect arrays");
        for (uint256 i = 0; i < recipients.length; i++) {
            UserClaimInfo memory data = UserClaimInfo(
            amounts[i],
            1650531600,
            amounts[i] / 4,
            true,
            true
        );
        claims[recipients[i]] = data;
        } 
    }

    // For emergency issues
    function rescueERC20() external onlyOwner {
        oru.safeTransfer(owner(), oru.balanceOf(address(this)));
    }
}
