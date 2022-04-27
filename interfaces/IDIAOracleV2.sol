// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;


interface IDIAOracleV2 {
     function getValue(string memory key) external view returns (uint128, uint128);
}
