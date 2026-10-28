// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IScientificOracle} from "./interfaces/IScientificOracle.sol";

/// @title Scientific Fund with External Oracle Validation
/// @author Proyecto Final Web3
/// @notice Escrow de financiación científica: los donantes aportan ETH, el responsable del proyecto
///         define hitos con evidencia en IPFS y los fondos de cada hito solo se liberan cuando
///         (1) la mayoría absoluta de auditores lo aprueba y (2) un oráculo externo valida la evidencia.
/// @dev Roles:
///      - Owner (responsable del proyecto): crea hitos y ejecuta la liberación; recibe los fondos.
///      - Auditores: lista fija definida en el constructor; votan una vez por hito.
///      - Cualquiera: puede donar y disparar la validación del oráculo (es determinista y no mueve fondos).
contract ScientificFundOracle is Ownable, ReentrancyGuard {
    /// @notice Datos de un hito de financiación.
    /// @param amount Monto en wei asignado al hito.
    /// @param votesFor Cantidad de votos de auditores a favor.
    /// @param votesAgainst Cantidad de votos de auditores en contra.
    /// @param released Indica si los fondos del hito ya fueron liberados.
    /// @param oracleApproved Indica si el oráculo externo aprobó la evidencia.
    /// @param title Nombre descriptivo del hito.
    /// @param ipfsHash CID de IPFS con la evidencia del hito.
    struct Milestone {
        uint128 amount;
        uint32 votesFor;
        uint32 votesAgainst;
        bool released;
        bool oracleApproved;
        string title;
        string ipfsHash;
    }

    /// @notice Contrato oráculo externo que valida la evidencia de los hitos.
    IScientificOracle public immutable oracle;

    /// @notice Total de ETH (wei) donado al contrato desde su creación.
    uint256 public totalRaised;
    /// @notice Total de ETH (wei) liberado al responsable del proyecto.
    uint256 public totalReleased;
    /// @notice Cantidad de hitos creados; también es el próximo ID de hito.
    uint256 public milestoneCount;

    /// @notice Lista de auditores habilitados para votar.
    address[] public auditors;
    /// @notice Indica si una dirección es auditor.
    mapping(address auditor => bool allowed) public isAuditor;
    /// @notice Indica si un auditor ya votó un hito determinado.
    mapping(uint256 milestoneId => mapping(address auditor => bool voted)) public hasVoted;
    /// @notice Hitos registrados por ID.
    mapping(uint256 milestoneId => Milestone data) public milestones;
    /// @notice Total donado por cada dirección.
    mapping(address donor => uint256 amount) public contributions;

    /// @notice Se emite cuando un donante aporta ETH al escrow.
    /// @param donor Dirección del donante.
    /// @param amount Monto donado en wei.
    /// @param totalRaised Total recaudado luego de la donación.
    event Contribution(address indexed donor, uint256 amount, uint256 totalRaised);
    /// @notice Se emite cuando el owner crea un hito.
    /// @param milestoneId ID del hito creado.
    /// @param title Título del hito.
    /// @param ipfsHash CID de IPFS con la evidencia.
    /// @param amount Monto asignado en wei.
    event MilestoneCreated(uint256 indexed milestoneId, string title, string ipfsHash, uint256 amount);
    /// @notice Se emite cuando un auditor vota un hito.
    /// @param milestoneId ID del hito votado.
    /// @param auditor Dirección del auditor.
    /// @param support `true` si aprueba, `false` si rechaza.
    event VoteCast(uint256 indexed milestoneId, address indexed auditor, bool support);
    /// @notice Se emite al registrar el resultado de la validación del oráculo.
    /// @param milestoneId ID del hito validado.
    /// @param approved Resultado devuelto por el oráculo.
    event OracleApproval(uint256 indexed milestoneId, bool approved);
    /// @notice Se emite cuando se liberan los fondos de un hito.
    /// @param milestoneId ID del hito liberado.
    /// @param amount Monto transferido en wei.
    /// @param recipient Dirección que recibió los fondos.
    event MilestoneReleased(uint256 indexed milestoneId, uint256 amount, address indexed recipient);

    /// @notice Se recibió la dirección cero donde se requiere una dirección válida.
    error ZeroAddress();
    /// @notice No se recibió ningún auditor en el constructor.
    error NoAuditors();
    /// @notice El título del hito está vacío.
    error EmptyTitle();
    /// @notice El CID de IPFS del hito está vacío.
    error EmptyIpfsHash();
    /// @notice El monto es cero o excede el máximo soportado.
    error InvalidAmount();
    /// @notice Quien llama no es auditor.
    /// @param caller Dirección que intentó votar.
    error NotAuditor(address caller);
    /// @notice El auditor ya votó este hito.
    /// @param milestoneId ID del hito.
    /// @param auditor Dirección del auditor.
    error AlreadyVoted(uint256 milestoneId, address auditor);
    /// @notice El hito no existe.
    /// @param milestoneId ID consultado.
    error MilestoneNotFound(uint256 milestoneId);
    /// @notice Los fondos del hito ya fueron liberados.
    /// @param milestoneId ID del hito.
    error MilestoneAlreadyReleased(uint256 milestoneId);
    /// @notice El hito no alcanzó la mayoría absoluta de auditores.
    /// @param votesFor Votos a favor obtenidos.
    /// @param required Votos a favor requeridos.
    error NoApproval(uint256 votesFor, uint256 required);
    /// @notice El oráculo no aprobó (o todavía no validó) la evidencia del hito.
    /// @param milestoneId ID del hito.
    error OracleRejected(uint256 milestoneId);
    /// @notice El contrato no tiene saldo suficiente para liberar el hito.
    /// @param available Saldo disponible en wei.
    /// @param required Monto requerido en wei.
    error InsufficientBalance(uint256 available, uint256 required);
    /// @notice Falló la transferencia de ETH al responsable del proyecto.
    error TransferFailed();

    /// @notice Verifica que el hito exista.
    /// @param _milestoneId ID del hito a verificar.
    modifier milestoneExists(uint256 _milestoneId) {
        _checkMilestoneExists(_milestoneId);
        _;
    }

    /// @notice Despliega el escrow con su responsable, auditores y oráculo.
    /// @param _projectOwner Responsable del proyecto (owner); recibe los fondos liberados.
    /// @param _auditors Direcciones de los auditores. Los duplicados se ignoran.
    /// @param _oracle Dirección del contrato oráculo que implementa IScientificOracle.
    constructor(address _projectOwner, address[] memory _auditors, address _oracle) Ownable(_projectOwner) {
        uint256 length = _auditors.length;
        if (length == 0) revert NoAuditors();
        if (_oracle == address(0)) revert ZeroAddress();

        oracle = IScientificOracle(_oracle);

        for (uint256 i; i < length;) {
            address auditor = _auditors[i];
            if (auditor == address(0)) revert ZeroAddress();
            if (!isAuditor[auditor]) {
                isAuditor[auditor] = true;
                auditors.push(auditor);
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Dona ETH al escrow del proyecto.
    /// @dev Solo actualiza contabilidad interna; no realiza llamadas externas.
    function contribute() external payable {
        if (msg.value == 0) revert InvalidAmount();

        contributions[msg.sender] += msg.value;
        uint256 newTotal = totalRaised + msg.value;
        totalRaised = newTotal;

        emit Contribution(msg.sender, msg.value, newTotal);
    }

    /// @notice Crea un hito de financiación. Solo el owner.
    /// @param _title Nombre descriptivo del hito.
    /// @param _ipfsHash CID de IPFS con la evidencia o documentación del avance.
    /// @param _amount Monto en wei asignado al hito.
    /// @return milestoneId ID asignado al nuevo hito.
    function createMilestone(string calldata _title, string calldata _ipfsHash, uint256 _amount)
        external
        onlyOwner
        returns (uint256 milestoneId)
    {
        if (bytes(_title).length == 0) revert EmptyTitle();
        if (bytes(_ipfsHash).length == 0) revert EmptyIpfsHash();
        if (_amount == 0 || _amount > type(uint128).max) revert InvalidAmount();

        milestoneId = milestoneCount;
        Milestone storage m = milestones[milestoneId];
        // forge-lint: disable-next-line(unsafe-typecast)
        m.amount = uint128(_amount); // seguro: validado contra type(uint128).max arriba
        m.title = _title;
        m.ipfsHash = _ipfsHash;
        milestoneCount = milestoneId + 1;

        emit MilestoneCreated(milestoneId, _title, _ipfsHash, _amount);
    }

    /// @notice Registra el voto de un auditor sobre un hito. Solo auditores, un voto por hito.
    /// @param _milestoneId ID del hito a evaluar.
    /// @param _support `true` para aprobar, `false` para rechazar.
    function voteMilestone(uint256 _milestoneId, bool _support) external milestoneExists(_milestoneId) {
        if (!isAuditor[msg.sender]) revert NotAuditor(msg.sender);
        if (hasVoted[_milestoneId][msg.sender]) revert AlreadyVoted(_milestoneId, msg.sender);

        Milestone storage m = milestones[_milestoneId];
        if (m.released) revert MilestoneAlreadyReleased(_milestoneId);

        hasVoted[_milestoneId][msg.sender] = true;
        if (_support) {
            ++m.votesFor;
        } else {
            ++m.votesAgainst;
        }

        emit VoteCast(_milestoneId, msg.sender, _support);
    }

    /// @notice Consulta al oráculo externo y guarda si aprueba la evidencia del hito.
    /// @dev Llamada inter-contrato de solo lectura (view); puede invocarla cualquiera.
    /// @param _milestoneId ID del hito a validar.
    /// @return approved Resultado devuelto por el oráculo.
    function validateMilestone(uint256 _milestoneId) external milestoneExists(_milestoneId) returns (bool approved) {
        Milestone storage m = milestones[_milestoneId];
        if (m.released) revert MilestoneAlreadyReleased(_milestoneId);

        approved = oracle.validateMilestone(owner(), _milestoneId, m.ipfsHash, m.amount);
        m.oracleApproved = approved;

        emit OracleApproval(_milestoneId, approved);
    }

    /// @notice Libera los fondos del hito al owner si tiene mayoría absoluta de auditores y aprobación del oráculo.
    /// @dev Sigue Checks-Effects-Interactions y está protegida con nonReentrant.
    /// @param _milestoneId ID del hito a liberar.
    function releaseMilestone(uint256 _milestoneId) external nonReentrant onlyOwner milestoneExists(_milestoneId) {
        // Checks
        Milestone storage m = milestones[_milestoneId];
        if (m.released) revert MilestoneAlreadyReleased(_milestoneId);
        if (!m.oracleApproved) revert OracleRejected(_milestoneId);

        uint256 votesFor = m.votesFor;
        uint256 required = approvalsRequired();
        if (votesFor < required) revert NoApproval(votesFor, required);

        uint256 amount = m.amount;
        uint256 balance = address(this).balance;
        if (balance < amount) revert InsufficientBalance(balance, amount);

        // Effects
        m.released = true;
        totalReleased += amount;

        // Interactions
        address recipient = owner();
        emit MilestoneReleased(_milestoneId, amount, recipient);
        (bool success,) = payable(recipient).call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    /// @notice Votos a favor necesarios para liberar un hito (mayoría absoluta de auditores).
    /// @return required Cantidad mínima de votos a favor.
    function approvalsRequired() public view returns (uint256 required) {
        return auditors.length / 2 + 1;
    }

    /// @notice Cantidad de auditores registrados.
    /// @return count Número de auditores.
    function auditorCount() external view returns (uint256 count) {
        return auditors.length;
    }

    /// @notice Indica si los fondos de un hito ya fueron liberados.
    /// @param _milestoneId ID del hito.
    /// @return released `true` si el hito fue liberado.
    function isMilestoneReleased(uint256 _milestoneId)
        external
        view
        milestoneExists(_milestoneId)
        returns (bool released)
    {
        return milestones[_milestoneId].released;
    }

    /// @notice Revierte si el hito no existe.
    /// @param _milestoneId ID del hito a verificar.
    function _checkMilestoneExists(uint256 _milestoneId) internal view {
        if (_milestoneId >= milestoneCount) revert MilestoneNotFound(_milestoneId);
    }
}
