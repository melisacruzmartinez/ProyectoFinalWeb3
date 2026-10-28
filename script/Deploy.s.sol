// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {ScientificOracle} from "../contracts/ScientificOracle.sol";
import {ScientificFundOracle} from "../contracts/ScientificFundOracle.sol";

/// @title Deploy
/// @notice Despliega ScientificOracle y ScientificFundOracle en una red EVM (ej. Sepolia).
/// @dev Variables de entorno (ver .env.example):
///      PRIVATE_KEY  -> deployer y owner del proyecto.
///      AUDITOR_1, AUDITOR_2, AUDITOR_3 -> direcciones públicas de los auditores.
contract Deploy is Script {
    /// @notice Las direcciones de auditor deben ser distintas de cero y únicas.
    error InvalidAuditorConfiguration();

    /// @notice Despliega el oracle y el escrow con el owner y auditores configurados en el entorno.
    /// @return oracle Dirección del contrato ScientificOracle desplegado.
    /// @return fund Dirección del contrato ScientificFundOracle desplegado.
    function run() external returns (ScientificOracle oracle, ScientificFundOracle fund) {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address projectOwner = vm.addr(deployerPk);

        address[] memory auditors = new address[](3);
        auditors[0] = vm.envAddress("AUDITOR_1");
        auditors[1] = vm.envAddress("AUDITOR_2");
        auditors[2] = vm.envAddress("AUDITOR_3");

        if (
            auditors[0] == address(0) || auditors[1] == address(0) || auditors[2] == address(0)
                || auditors[0] == auditors[1] || auditors[0] == auditors[2] || auditors[1] == auditors[2]
        ) {
            revert InvalidAuditorConfiguration();
        }

        vm.startBroadcast(deployerPk);
        oracle = new ScientificOracle();
        fund = new ScientificFundOracle(projectOwner, auditors, address(oracle));
        vm.stopBroadcast();

        console2.log("ScientificOracle     :", address(oracle));
        console2.log("ScientificFundOracle :", address(fund));
        console2.log("Owner                :", projectOwner);
        console2.log("Auditor 1            :", auditors[0]);
        console2.log("Auditor 2            :", auditors[1]);
        console2.log("Auditor 3            :", auditors[2]);
    }
}
