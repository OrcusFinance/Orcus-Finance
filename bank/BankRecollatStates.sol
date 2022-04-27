// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "../common/OrcusProtocol.sol";

contract BankRecollatStates is OrcusProtocol {
    event LogToggleRecollatPaused(bool isPaused);
    event LogSetPoolCeiling(uint256 poolCeiling);
    event LogSetRctMaxPerHour(uint256 rctMaxPerHour);

    uint256 public bonusRate = 5000; // Bonus rate on ORU minted during recollateralize(); 6 decimals of precision
    mapping(uint256 => uint256) public rctHourlyCum; // Epoch hour ->  ORU out in that hour
    uint256 public rctMaxPerHour = 0; // Infinite if 0

    bool public recollatPaused = false;

    uint256 public poolCeiling = 10000000e6; // 10 mil USDC to start

    function toggleRecollatPaused() external onlyOwnerOrOperator {
        recollatPaused = !recollatPaused;
        emit LogToggleRecollatPaused(recollatPaused);
    }

    function setPoolCeiling(uint256 _poolCeiling) external onlyOwnerOrOperator {
        poolCeiling = _poolCeiling;
        emit LogSetPoolCeiling(poolCeiling);
    }

    function setRctMaxPerHour(uint256 _rctMaxPerHour)
        external
        onlyOwnerOrOperator
    {
        rctMaxPerHour = _rctMaxPerHour;
        emit LogSetRctMaxPerHour(rctMaxPerHour);
    }
}
