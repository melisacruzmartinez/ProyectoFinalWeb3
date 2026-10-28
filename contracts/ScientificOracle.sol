// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IScientificOracle} from "./interfaces/IScientificOracle.sol";

/// @title Scientific Oracle (MVP)
/// @author Proyecto Final Web3
/// @notice Validador externo de hitos. ScientificFundOracle lo consulta mediante una
///         llamada inter-contrato antes de permitir la liberación de fondos.
/// @dev MVP determinista y sin estado: aprueba un hito si el proyecto es una dirección válida,
///      la evidencia (CID de IPFS) no está vacía y el monto es mayor a cero.
///      En una fase futura se reemplaza por un oráculo con firma de validadores o Chainlink Functions
///      sin modificar el contrato de fondos, ya que ambos comparten la interfaz IScientificOracle.
contract ScientificOracle is IScientificOracle {
    /// @inheritdoc IScientificOracle
    function validateMilestone(address project, uint256, string calldata ipfsHash, uint256 amount)
        external
        pure
        returns (bool)
    {
        return project != address(0) && bytes(ipfsHash).length != 0 && amount != 0;
    }
}
