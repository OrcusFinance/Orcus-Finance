// SPDX-License-Identifier: UNLICENSE

pragma solidity 0.8.4;

import "../ERC20/OrcusERC20.sol";

contract MockOrcusERC20 is OrcusERC20 {
    constructor(address _bank) OrcusERC20("Z Token", "ZMOCK", _bank) {
        // do nothing
    }

    // @notice Must only be called by anyone! haha!
    function mint(address _to, uint256 _amount) public {
        require(_to != address(0));
        require(_amount > 0);
        _mint(_to, _amount);
    }

    function setBalance(address _to, uint256 _amount) public {
        _burn(_to, balanceOf(_to));
        _mint(_to, _amount);
    }

    function mintByFarm(address _to, uint256 _amt) public override {
        _mint(_to, _amt);
    }
}
