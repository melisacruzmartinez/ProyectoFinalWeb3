// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {ScientificOracle} from "../contracts/ScientificOracle.sol";
import {ScientificFundOracle} from "../contracts/ScientificFundOracle.sol";

/// @title Deploy
/// @notice Despliega ScientificOracle y ScientificFundOracle en una red EVM (ej. Sepolia).
/// @dev Variables de entorno (ver .env.example):
///      PRIVATE_KEY  -> deployer y owner del proyecto.
///      AUDITOR_1_PK, AUDITOR_2_PK, AUDITOR_3_PK -> se usan solo para derivar las direcciones de los auditores.
contract Deploy is Script {
    function run() external returns (ScientificOracle oracle, ScientificFundOracle fund) {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address projectOwner = vm.addr(deployerPk);

        address[] memory auditors = new address[](3);
        auditors[0] = vm.addr(vm.envUint("AUDITOR_1_PK"));
        auditors[1] = vm.addr(vm.envUint("AUDITOR_2_PK"));
        auditors[2] = vm.addr(vm.envUint("AUDITOR_3_PK"));

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
