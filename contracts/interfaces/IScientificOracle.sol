// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IScientificOracle
/// @author Proyecto Final Web3
/// @notice Interfaz del validador externo que confirma la evidencia de un hito científico.
interface IScientificOracle {
    /// @notice Valida si la evidencia de un hito es aceptable para liberar fondos.
    /// @param project Dirección del responsable del proyecto que recibirá los fondos.
    /// @param milestoneId Identificador del hito dentro del contrato de fondos.
    /// @param ipfsHash CID de IPFS con la evidencia del hito.
    /// @param amount Monto en wei asignado al hito.
    /// @return approved `true` si el oráculo aprueba el hito, `false` en caso contrario.
    function validateMilestone(address project, uint256 milestoneId, string calldata ipfsHash, uint256 amount)
        external
        view
        returns (bool approved);
}
