// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {ScientificFundOracle} from "../contracts/ScientificFundOracle.sol";

/// @title Interact
/// @notice Ejecuta el flujo principal completo on-chain sobre un ScientificFundOracle ya desplegado:
///         fondeo de gas a auditores -> donación -> creación de hito -> 2 votos a favor -> validación del oráculo -> liberación.
/// @dev Variables de entorno: PRIVATE_KEY (owner/donante), AUDITOR_1_PK, AUDITOR_2_PK, FUND_ADDRESS.
///      Opcionales: DONATION_WEI (default 0.01 ether), MILESTONE_WEI (default 0.005 ether), AUDITOR_GAS_WEI (default 0.003 ether).
contract Interact is Script {
    /// @notice Se intentó ejecutar una acción de auditor con una cuenta no registrada en el escrow.
    /// @param auditor Dirección derivada de una clave privada que no está registrada como auditor.
    error AuditorNotRegistered(address auditor);

    /// @notice Ejecuta el flujo principal on-chain usando las cuentas definidas en el entorno.
    /// @dev Requiere que las claves de auditor correspondan a auditores registrados en el escrow.
    function run() external {
        uint256 ownerPk = vm.envUint("PRIVATE_KEY");
        uint256 auditor1Pk = vm.envUint("AUDITOR_1_PK");
        uint256 auditor2Pk = vm.envUint("AUDITOR_2_PK");
        ScientificFundOracle fund = ScientificFundOracle(payable(vm.envAddress("FUND_ADDRESS")));

        uint256 donation = vm.envOr("DONATION_WEI", uint256(0.01 ether));
        uint256 milestoneAmount = vm.envOr("MILESTONE_WEI", uint256(0.005 ether));
        uint256 auditorGas = vm.envOr("AUDITOR_GAS_WEI", uint256(0.003 ether));

        address auditor1 = vm.addr(auditor1Pk);
        address auditor2 = vm.addr(auditor2Pk);

        if (!fund.isAuditor(auditor1)) revert AuditorNotRegistered(auditor1);
        if (!fund.isAuditor(auditor2)) revert AuditorNotRegistered(auditor2);

        // 1) Owner: fondea gas a los auditores (si hace falta), dona y crea el hito.
        vm.startBroadcast(ownerPk);
        if (auditor1.balance < auditorGas) payable(auditor1).transfer(auditorGas);
        if (auditor2.balance < auditorGas) payable(auditor2).transfer(auditorGas);
        fund.contribute{value: donation}();
        uint256 id = fund.createMilestone("Fase 1", "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG", milestoneAmount);
        vm.stopBroadcast();

        // 2) Auditores: votan a favor (2 de 3 = mayoría absoluta).
        vm.broadcast(auditor1Pk);
        fund.voteMilestone(id, true);
        vm.broadcast(auditor2Pk);
        fund.voteMilestone(id, true);

        // 3) Owner: dispara la validación del oráculo (llamada inter-contrato) y libera los fondos.
        vm.startBroadcast(ownerPk);
        fund.validateMilestone(id);
        fund.releaseMilestone(id);
        vm.stopBroadcast();

        console2.log("Milestone ID   :", id);
        console2.log("Released       :", fund.isMilestoneReleased(id));
        console2.log("Total raised   :", fund.totalRaised());
        console2.log("Total released :", fund.totalReleased());
    }
}
