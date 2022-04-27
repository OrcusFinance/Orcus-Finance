// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IDIAOracleV2.sol";
import "../interfaces/IPriceOracle.sol";
import "../common/OrcusProtocol.sol";
import "./TwapOracle.sol";

contract PriceOracle is OrcusProtocol, IPriceOracle {
    IDIAOracleV2 public immutable DIAOracleV2;
    TwapOracle public ousdCollatTwapOracle;
    TwapOracle public oruCollatTwapOracle;

    event OusdOracleUpdated(address indexed newOracle);
    event OruOracleUpdated(address indexed newOracle);

    constructor(
        address _DIAOracleV2Address,
        address _ousdCollatTwapOracle,
        address _oruCollatTwapOracle
    ) {
        DIAOracleV2 = IDIAOracleV2(_DIAOracleV2Address);
        setOusdOracle(_ousdCollatTwapOracle);
        setOruOracle(_oruCollatTwapOracle);
    }

    function collatPrice() public view override returns (uint256) {
        (uint128 _price,) = IDIAOracleV2(DIAOracleV2).getValue("USDC/USD");

        uint8 _decimals = 8;
        return (uint256(_price) * PRICE_PRECISION) / (10**_decimals);
    }

    function ousdPrice() external view override returns (uint256) {
        uint256 _collatPrice = collatPrice();
        uint256 _ousdPrice = ousdCollatTwapOracle.consult(OUSD_PRECISION);
        require(_ousdPrice > 0, "Oracle: invalid ousd price");

        return (_collatPrice * _ousdPrice) / PRICE_PRECISION;
    }

    function oruPrice() external view override returns (uint256) {
        uint256 _collatPrice = collatPrice();
        uint256 _oruPrice = oruCollatTwapOracle.consult(ORU_PRECISION);
        require(_oruPrice > 0, "Oracle: invalid oru price");
        return (_collatPrice * _oruPrice) / PRICE_PRECISION;
    }

    function setOusdOracle(address _oracle) public onlyOwner {
        ousdCollatTwapOracle = TwapOracle(_oracle);
        emit OusdOracleUpdated(_oracle);
    }

    function setOruOracle(address _oracle) public onlyOwner {
        oruCollatTwapOracle = TwapOracle(_oracle);
        emit OruOracleUpdated(_oracle);
    }
}
