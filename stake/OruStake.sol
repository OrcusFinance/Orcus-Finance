// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "../interfaces/IProfitController.sol";
import "../interfaces/IORUStake.sol";
import "../common/OrcusProtocol.sol";

contract OruStake is
    ERC20("OruStake", "xORU"),
    IOruStake,
    Initializable,
    OrcusProtocol
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public oru;
    bool public stakePaused = false;

    uint256 public constant LOCK_DURATION = 86400 * 7; // 7 days
    uint256 public constant EPOCH_PERIOD = 1 days;

    struct EpochDistribution {
        uint256 lastRewardTime;
        uint256 lockAmount;
        uint256 stepAmount;
    }

    struct UserInfo {
        uint256 unlockTime;
        uint256 xOruAmount;
    }

    EpochDistribution public epoch;

    address public profitController;

    mapping(address => UserInfo) public userLocks;

    modifier onlyProfitController() {
        require(
            msg.sender == owner() || msg.sender == profitController,
            "Only profit controller"
        );
        _;
    }

    event ProfitDistributed(uint256 amount);
    event ProfitControllerUpdated(address profitController);
    event StakePaused();

    constructor(IERC20 _oru) {
        oru = _oru;
    }

    function init(address _profitController) external initializer onlyOwner {
        setProfitController(_profitController);
    }

    function calcAccAmt() public view returns (uint256) {
        if (block.timestamp < epoch.lastRewardTime) {
            return 0;
        }
        uint256 _now = block.timestamp;
        uint256 epochElapsed = _now - epoch.lastRewardTime;
        uint256 accAmt = epoch.stepAmount * epochElapsed;
        return accAmt;
    }

    function updateStakeLock() public {
        uint256 accAmt = calcAccAmt();
        if (epoch.lockAmount > accAmt) {
            epoch.lockAmount -= accAmt;
        } else {
            epoch.lockAmount = 0;
        }
        epoch.lastRewardTime = block.timestamp;
    }

    function pendingxOru(address _user) public view returns (uint256) {
        uint256 totalShares = totalSupply();

        uint256 lockAcc = epoch.lockAmount - calcAccAmt();
        uint256 adjustedTotalOru = oru.balanceOf(address(this)).sub(lockAcc);
        uint256 xOruAmt = balanceOf(_user).mul(adjustedTotalOru).div(
            totalShares
        );
        return xOruAmt;
    }

    function stake(uint256 _amount) public nonReentrant {
        require(!stakePaused, "Stake is paused");
        updateStakeLock();

        uint256 _unlockTime = block.timestamp.add(LOCK_DURATION);
        uint256 _totalOru = oru.balanceOf(address(this));
        uint256 _totalShares = totalSupply();

        uint256 _xOruOut = 0;
        if (_totalShares == 0 || _totalOru == 0) {
            _xOruOut = _amount;
        } else {
            uint256 _adjustedTotalOru = _totalOru.sub(epoch.lockAmount);
            _xOruOut = _amount.mul(_totalShares).div(_adjustedTotalOru);
        }

        require(_xOruOut > 0, "Stake: Out is 0");

        UserInfo storage userInfo = userLocks[msg.sender];
        userInfo.unlockTime = _unlockTime;
        userInfo.xOruAmount += _xOruOut;

        _mint(msg.sender, _xOruOut);
        oru.safeTransferFrom(msg.sender, address(this), _amount);
    }

    function unstake(uint256 _share) public nonReentrant {
        require(!stakePaused, "Stake: Paused");
        require(_share <= balanceOf(msg.sender), "Stake: >balance");

        UserInfo storage userInfo = userLocks[msg.sender];
        require(userInfo.unlockTime <= block.timestamp, "Stake: Not expired");
        require(userInfo.xOruAmount >= _share, "Stake: Not Staked");

        updateStakeLock();

        uint256 totalShares = totalSupply();
        uint256 totalOru = oru.balanceOf(address(this));

        uint256 adjustedTotalOru = totalOru.sub(epoch.lockAmount);
        uint256 oruAmount = _share.mul(adjustedTotalOru).div(totalShares);

        userInfo.xOruAmount -= _share;
        _burn(msg.sender, _share);
        oru.safeTransfer(msg.sender, oruAmount);
    }

    function oruPerShare() external view returns (uint256) {
        uint256 totalShares = totalSupply();
        uint256 totalOru = oru.balanceOf(address(this));

        if (totalShares == 0 || totalOru == 0) {
            return 1e18;
        }

        uint256 adjustedTotalOru = totalOru.sub(epoch.lockAmount).add(
            calcAccAmt()
        );

        uint256 oruAmt = (adjustedTotalOru).mul(1e18).div(totalShares);
        return oruAmt;
    }

    function userLockInfo(address _user)
        external
        view
        returns (uint256, uint256)
    {
        UserInfo memory _userInfo = userLocks[_user];
        uint256 unlockTime = _userInfo.unlockTime;
        if (unlockTime == 0) {
            return (0, 0);
        }
        uint256 lockRemaining = unlockTime.sub(block.timestamp);
        return (unlockTime, lockRemaining);
    }

    function distribute(uint256 _amount)
        external
        override
        onlyProfitController
    {
        require(_amount != 0, "Amount must be greater than 0");
        updateStakeLock();

        uint256 _newLockAmount = epoch.lockAmount.add(_amount);
        uint256 _stepAmount = _newLockAmount.div(EPOCH_PERIOD);
        epoch = EpochDistribution({
            lastRewardTime: block.timestamp,
            lockAmount: _newLockAmount,
            stepAmount: _stepAmount
        });
        emit ProfitDistributed(_amount);
        oru.safeTransferFrom(profitController, address(this), _amount);
    }

    function setStakePaused() public onlyOwnerOrOperator {
        stakePaused = !stakePaused;
        emit StakePaused();
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

    function setProfitController(address _profitController) public onlyOwner {
        require(_profitController != address(0), "Invalid address");
        profitController = _profitController;
        emit ProfitControllerUpdated(_profitController);
    }
}
