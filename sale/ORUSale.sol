pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IOUSDERC20.sol";

contract ORUSale is Ownable {

    using SafeERC20 for IOrcusERC20;
    using SafeERC20 for IERC20;

    IOrcusERC20 public oru;
    IERC20 public usdc;
    bool public saleStarted;
    bool public saleFinished;

    struct UserClaimInfo {
        uint256 oruAmt;
        uint256 deposited;
        uint256 lastClaimed;
        uint256 distributionAmt;
        bool firstTimeClaimed;
        bool userExist;
    }

    uint256 public constant INTERVAL_BETWEEN_CLAIMS = 14 days; // 2 weeks
    uint256 public constant MAX_USD_DEPOSIT_AMOUNT = 5000000000; // 5000 USDC
    uint256 public constant MISSING_DECIMALS = 1e12;
    uint256 public constant ORU_PRICE_MULTIPLIER = 20;

    mapping (address => UserClaimInfo) public claims;

    constructor(address _oru, address _usdc) {
        oru = IOrcusERC20(_oru);
        usdc = IERC20(_usdc);
    }

    function startSale() public onlyOwner {
        saleStarted = true;
        saleFinished = false;
    }

    function deposit(uint usdcAmt) public {

        require(saleStarted, "Sale does not started yet.");
        require(!saleFinished, "Sale is finished");

        uint oruBoughtAmt = (usdcAmt * MISSING_DECIMALS) * ORU_PRICE_MULTIPLIER;
        uint distributionAmt = oruBoughtAmt / 5;

        if (!claims[msg.sender].userExist) {
            require(usdcAmt <= MAX_USD_DEPOSIT_AMOUNT, "Max deposit amount is 5000 USDC");
            claims[msg.sender] = UserClaimInfo(oruBoughtAmt, usdcAmt, 0, distributionAmt, false, true);
            usdc.transferFrom(msg.sender, address(this), usdcAmt);
        }

        else {
            uint newOruAmt = claims[msg.sender].oruAmt + oruBoughtAmt;
            uint newDistributionAmt = newOruAmt / 5;

            require(usdcAmt + claims[msg.sender].deposited <= MAX_USD_DEPOSIT_AMOUNT, "Sum deposit amount shouldn't be greater than 5000 USDC");

            usdc.transferFrom(msg.sender, address(this), usdcAmt);
            claims[msg.sender] = UserClaimInfo(newOruAmt, usdcAmt, 0, newDistributionAmt, false, true);
        }
    }

    function claim() public {
        require(!saleStarted, "Sale does not finished yet.");
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

    function finishSale() public onlyOwner {
        saleStarted = false;
        saleFinished = true;
        uint256 usdcBalance = usdc.balanceOf(address(this));

        usdc.safeTransfer(owner(), usdcBalance);
    }


    function sendCarryOveredORU() public onlyOwner {

        require(saleFinished, "Sale isn't finished");
        uint oruBal = oru.balanceOf(address(this));

        oru.safeTransfer(owner(), oruBal);
    }
}
