// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./OrcusERC20.sol";

contract oUSD is OrcusERC20 {
    uint256 public constant GENESIS_SUPPLY = 100 ether;

    constructor(address _bank) OrcusERC20("oUSD", "oUSD", _bank) {
        _mint(msg.sender, GENESIS_SUPPLY);
    }

    function mintByFarm(address _to, uint256 _amt) public override onlyFarm {
        require(false, "Farm can't mint");
        emit LogMint(_to, _amt);
    }
}
