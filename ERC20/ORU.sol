// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "./OrcusERC20.sol";

contract ORU is OrcusERC20 {
    uint256 public constant GENESIS_SUPPLY = 1_000_000 ether; // minted at genesis for liquidity pool seeding

    uint256 public constant COMMUNITY_REWARD_ALLOCATION = 700_000_000 ether;
    uint256 public constant TEAM_FUND_ALLOCATION = 175_000_000 ether;
    uint256 public constant V1_REWARD_AMT = 87_500_000 ether;
    uint256 public constant TEAM_FUND_VESTING_DURATION = 1095 days; // 3 years
    uint256 public constant TEAM_FUND_EMISSION_RATE =
        TEAM_FUND_ALLOCATION / TEAM_FUND_VESTING_DURATION;
    uint256 private constant ONE_YEAR = 365 days;
    uint256 public constant VESTING_DECREASING_RATIO = 290988; // 29.0988%

    uint256 private constant RATIO_PRECISION = 1e6;

    uint256 public oruMintedByFarm;

    address public treasury;
    address public team;

    struct TeamVesting {
        uint256 startTime;
        uint256 vestedAmount;
        uint256 lastClaimed;
    }
    TeamVesting public teamVesting;

    event TreasuryUpdated(address treasury);
    event SetTeam(address team);

    constructor(
        address _bank,
        uint256 _vestingStartTime,
        address _team,
        address _treasury
    ) OrcusERC20("Orcus Token", "ORU", _bank) {
        _mint(msg.sender, GENESIS_SUPPLY + V1_REWARD_AMT);
        _setTeamVesting(_vestingStartTime);
        team = _team;
        setTreasury(_treasury);
    }

    function mintByFarm(address _to, uint256 _amt) public override onlyFarm {
        require(_amt > 0, "ORU: Aero amount");
        require(_to != address(0), "ORU: Zero address");
        require(
            oruMintedByFarm < COMMUNITY_REWARD_ALLOCATION,
            "ORU: Reward alloc zero"
        );

        if (oruMintedByFarm + _amt > COMMUNITY_REWARD_ALLOCATION) {
            uint256 amtLeft = COMMUNITY_REWARD_ALLOCATION - oruMintedByFarm;
            oruMintedByFarm += amtLeft;
            _mint(_to, amtLeft);
        } else {
            oruMintedByFarm += _amt;
            _mint(_to, _amt);
        }

        emit LogMint(_to, _amt);
    }

    function _setTeamVesting(uint256 _vestingStartTime) internal {
        teamVesting.startTime = _vestingStartTime;
        teamVesting.lastClaimed = _vestingStartTime;
    }

    function unclaimedTeamFund() public view returns (uint256) {
        uint256 _now = block.timestamp;

        if (_now <= teamVesting.lastClaimed) {
            return 0;
        }

        uint256 _fromEpoch = _now - teamVesting.startTime;
        uint256 _years = _fromEpoch / ONE_YEAR;

        uint256 _emissionRate = TEAM_FUND_EMISSION_RATE;
        for (uint256 i = 0; i < _years; i++) {
            _emissionRate =
                _emissionRate -
                ((_emissionRate * VESTING_DECREASING_RATIO) / RATIO_PRECISION);
        }

        uint256 _timeElapsed = _now - teamVesting.lastClaimed;
        uint256 _available = Math.min(
            _timeElapsed * _emissionRate,
            TEAM_FUND_ALLOCATION - teamVesting.vestedAmount
        );

        return _available;
    }

    function claimTeamFundRewards(address _to) external {
        require(msg.sender == team, "ORU: Team only");
        require(_to != address(0), "ORU: Address zero");
        require(treasury != address(0), "ORU: Treasury not set");

        uint256 _pending = unclaimedTeamFund();
        require(_pending > 0, "ORU: Nothing to claim");

        uint256 treasuryAmt = (_pending * 10) / 45; // 1/4.5 of team alloc
        uint256 teamAmt = _pending - treasuryAmt;

        _mint(_to, teamAmt);
        _mint(treasury, treasuryAmt);

        teamVesting.lastClaimed = block.timestamp;
        teamVesting.vestedAmount += _pending;
    }

    function setTreasury(address _treasury) public onlyOwner {
        require(_treasury != address(0), "ORU: Invalid treasury");
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }
}
