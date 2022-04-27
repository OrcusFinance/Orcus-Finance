// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract OrcusProtocol is Ownable, ReentrancyGuard {
    uint256 internal constant RATIO_PRECISION = 1e6;
    uint256 internal constant PRICE_PRECISION = 1e6;
    uint256 internal constant USDC_PRECISION = 1e6;
    uint256 internal constant MISSING_PRECISION = 1e12;
    uint256 internal constant OUSD_PRECISION = 1e18;
    uint256 internal constant ORU_PRECISION = 1e18;
    uint256 internal constant SWAP_FEE_PRECISION = 1e4;

    address internal constant ADDRESS_USDC =
        0x6a2d262D56735DbA19Dd70682B39F6bE9a931D98;
    address internal constant ADDRESS_WASTR =
        0xAeaaf0e2c81Af264101B9129C00F4440cCF0F720;

    address public operator;

    event OperatorUpdated(address indexed newOperator);

    constructor() {
        setOperator(msg.sender);
    }

    modifier onlyNonContract() {
        require(msg.sender == tx.origin, "Orcus: sender != origin");
        _;
    }

    modifier onlyOwnerOrOperator() {
        require(
            msg.sender == owner() || msg.sender == operator,
            "Orcus: sender != operator"
        );
        _;
    }

    function setOperator(address _operator) public onlyOwner {
        require(_operator != address(0), "Orcus: Invalid operator");
        operator = _operator;
        emit OperatorUpdated(operator);
    }

    function _currentBlockTs() internal view returns (uint64) {
        return SafeCast.toUint64(block.timestamp);
    }
}
