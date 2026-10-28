# Proyecto Final Web3 - Financiación transparente de la investigación científica

## I. Resumen ejecutivo

Este proyecto propone una solución basada en tecnología *blockchain* para financiar la investigación científica y proyectos de interés público. El objetivo principal es eliminar la opacidad, el control discrecional y los posibles sesgos en la asignación de capital, utilizando contratos inteligentes (*smart contracts*) para automatizar las donaciones, la gobernanza y la liberación de fondos conforme a hitos verificables.

La solución se articula en torno a un modelo de depósito en garantía (*escrow*) transparente, en el que los fondos permanecen bloqueados en un contrato y solo se liberan cuando varios auditores independientes validan el progreso y las pruebas vinculadas a cada hito. Este diseño reduce el riesgo de corrupción, arbitrariedad administrativa y presentación selectiva de resultados.

## II. Relevancia de la tecnología *blockchain* para este problema

El uso de *blockchain* en la financiación científica no es una mera tendencia tecnológica, sino una respuesta estructural a las deficiencias de los sistemas centralizados:

- Eliminación de intermediarios opacos: los fondos no permanecen en cuentas administrativas poco claras, sino que están sujetos a reglas codificadas en contratos inteligentes.
- Transparencia y capacidad de auditoría: cualquier donante, institución o ciudadano puede rastrear cómo se asignan los fondos y qué hitos han sido aprobados.
- Reducción de la corrupción y los sesgos comerciales: el sistema requiere una estructura de gobernanza multifirma (*multi-signature*) y referencias a pruebas inmutables, como los *hashes* de IPFS.
- Rendición de cuentas en tiempo real: los hitos y las votaciones quedan registrados en la cadena (*on-chain*), lo que permite verificar de forma transparente el progreso y la asignación de recursos a lo largo del tiempo.

## III. Planteamiento del problema

La financiación científica suele enfrentarse a desafíos como:
- falta de trazabilidad;
- decisiones discrecionales tomadas por un único administrador;
- divulgación selectiva de resultados;
- dependencia de instituciones centralizadas opacas.

Esta solución aborda dichas debilidades mediante la creación de un mecanismo de gobernanza en el que los fondos solo se liberan si el hito correspondiente cuenta con la aprobación suficiente por parte de auditores independientes y, en una versión ampliada, de validadores externos.

## IV. Valor empresarial y técnico

El sistema propuesto aporta valor en dos niveles:

- Valor empresarial: mejora la confianza entre donantes, instituciones y la sociedad, al tiempo que permite una financiación más resiliente para la investigación.
- Valor técnico: demuestra el uso de patrones seguros de contratos inteligentes, trazabilidad basada en eventos y una lógica de gobernanza aplicada al mundo real dentro de un entorno *blockchain*.

## V. Estructura del repositorio

## V. Arquitectura

```text
                ┌──────────────────────────┐   validateMilestone()   ┌─────────────────────┐
 Donantes ────► │   ScientificFundOracle   │ ──────────────────────► │  ScientificOracle   │
 contribute()   │  (escrow + gobernanza)   │ ◄────── bool ────────── │ (validador externo) │
                └──────────────────────────┘                         └─────────────────────┘
 Owner: createMilestone / releaseMilestone      Auditores: voteMilestone
```

| Contrato | Rol |
|---|---|
| `contracts/ScientificFundOracle.sol` | Escrow principal: donaciones, hitos, votación de auditores, liberación de fondos. Usa `Ownable` y `ReentrancyGuard` de OpenZeppelin. |
| `contracts/ScientificOracle.sol` | Oráculo propio que valida la evidencia de cada hito. Se consulta mediante **llamada inter-contrato**. |
| `contracts/interfaces/IScientificOracle.sol` | Interfaz común: permite reemplazar el oráculo sin tocar el escrow. |

### Flujo principal
1. Cualquier donante llama a `contribute()` y envía ETH al escrow.
2. El owner (responsable del proyecto) crea un hito con `createMilestone(title, ipfsHash, amount)`.
3. Los auditores votan con `voteMilestone(id, support)`; se requiere **mayoría absoluta** (`auditores/2 + 1`).
4. Cualquiera llama a `validateMilestone(id)`: el escrow consulta al `ScientificOracle` y guarda el resultado.
5. El owner llama a `releaseMilestone(id)`: si hay mayoría + aprobación del oráculo + saldo, se transfieren los fondos.

### Roles y permisos
| Rol | Puede |
|---|---|
| Owner | `createMilestone`, `releaseMilestone` (recibe los fondos liberados) |
| Auditor | `voteMilestone` (un voto por hito) |
| Cualquiera | `contribute`, `validateMilestone`, lecturas |

### Decisiones de seguridad y gas
- **Checks-Effects-Interactions** en `releaseMilestone` + `nonReentrant` (cubierto con test de reentrada).
- **Custom errors con parámetros** en lugar de strings.
- `oracle` es `immutable`; el struct `Milestone` empaqueta `amount (uint128)`, votos (`uint32`) y flags en un solo slot.
- `calldata` para strings de entrada; lecturas de storage cacheadas en variables locales; `unchecked` en el incremento del loop.
- `title` e `ipfsHash` se guardan como `string` porque son necesarios para la solución (el CID de IPFS no entra en `bytes32`).
- NatSpec completo en contratos, eventos, errores, modifiers y funciones.

## VI. Estructura del repositorio

```text
ProyectoFinalWeb3/
├── contracts/
│   ├── ScientificFundOracle.sol
│   ├── ScientificOracle.sol
│   └── interfaces/IScientificOracle.sol
├── test/ScientificFundOracle.t.sol     # 34 tests (unit, revert, reentrancy, fuzz)
├── script/
│   ├── Deploy.s.sol                    # deploy de oráculo + escrow
│   └── Interact.s.sol                  # flujo completo on-chain
├── frontend/                           # demo React + ethers
├── .env.example
└── foundry.toml
```

## VII. Instalación y compilación

Requisitos: [Foundry](https://book.getfoundry.sh/getting-started/installation), Node 20+ (frontend), Python 3 (Slither).

```bash
git clone --recurse-submodules https://github.com/melisacruzmartinez/ProyectoFinalWeb3.git
cd ProyectoFinalWeb3
forge build
```

## VIII. Tests y coverage

```bash
forge test -vv
forge coverage --no-match-coverage "script|test"
```

Resultado: **34 tests pasan (100%)**.

| Archivo | Lines | Statements | Branches | Funcs |
|---|---|---|---|---|
| ScientificFundOracle.sol | 100% | 100% | 100% | 100% |
| ScientificOracle.sol | 100% | 100% | 100% | 100% |

Incluye: flujo completo exitoso, dos hitos consecutivos, todos los custom errors, rechazo del oráculo, fallo de transferencia, intento de reentrada y un test de fuzzing sobre donaciones.

## IX. Análisis estático (Slither)

```bash
pip install slither-analyzer
slither . --filter-paths "lib/|test/|script/" --exclude-dependencies
```

| Detector | Ubicación | Estado | Justificación |
|---|---|---|---|
| `low-level-calls` | `releaseMilestone` → `recipient.call{value: amount}("")` | **Aceptado** | Es el patrón recomendado para enviar ETH (evita el límite de 2300 gas de `transfer`). Se verifica el retorno (`TransferFailed`), se aplica CEI y `nonReentrant`. |
| `naming-convention` | Parámetros con prefijo `_` | **Aceptado** | Convención de estilo del equipo para distinguir parámetros de variables de estado. Sin impacto en seguridad. |

Findings corregidos respecto de la versión anterior: chequeo de saldo que contaba dos veces lo liberado, función del oráculo que debía ser `pure`, variable `oracle` que debía ser `immutable`, `ReentrancyGuard` innecesario en `contribute`.

## X. Deploy y uso

### 1. Configurar variables
```bash
cp .env.example .env
cast wallet new   # repetir 3 veces y copiar las private keys en AUDITOR_1_PK..3
# completar PRIVATE_KEY (con Sepolia ETH) y ETHERSCAN_API_KEY
source .env
```

### 2. Deploy + verificación en Sepolia
```bash
forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify
```

### 3. Ejecutar el flujo principal on-chain
```bash
export FUND_ADDRESS=<dirección de ScientificFundOracle>
forge script script/Interact.s.sol --rpc-url sepolia --broadcast
```

### 4. Demo local con Anvil + MetaMask

Terminal 1 – nodo local:
```bash
anvil
```

Terminal 2 – deploy con las cuentas de prueba de Anvil (cuenta 0 = owner, 1-3 = auditores; claves públicas de Anvil, **solo para red local**):
```bash
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
export AUDITOR_1_PK=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
export AUDITOR_2_PK=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
export AUDITOR_3_PK=0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6
forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
```
En una instancia limpia de Anvil, `ScientificFundOracle` queda en `0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512`, que es la dirección configurada en `frontend/src/contract.js`.

En MetaMask: agregar la red `Anvil Local` (RPC `http://127.0.0.1:8545`, chain ID `31337`) e importar una cuenta de Anvil.

Terminal 3 – frontend:
```bash
cd frontend
npm install
npm run dev
```
Abrir <http://127.0.0.1:5173>, conectar MetaMask y donar. Anvil y Sepolia son redes distintas: las transacciones locales no aparecen en Etherscan.

## XI. Red y contratos desplegados

Red: **Sepolia** (chainId 11155111)

| Contrato | Dirección | Código verificado |
|---|---|---|
| ScientificOracle | `TODO` | TODO |
| ScientificFundOracle | `TODO` | TODO |

### Transacciones reales del flujo principal

| Paso | Tx |
|---|---|
| Donación (`contribute`) | TODO |
| Crear hito (`createMilestone`) | TODO |
| Voto auditor 1 | TODO |
| Voto auditor 2 | TODO |
| Validación oráculo (`validateMilestone`) | TODO |
| Liberación (`releaseMilestone`) | TODO |

## XII. Limitaciones conocidas del MVP

- El oráculo es determinista: valida formato (dirección, CID no vacío, monto > 0), no el contenido científico de la evidencia.
- La lista de auditores es fija desde el deploy (no hay alta/baja).
- No hay devolución a donantes si un hito es rechazado ni plazos de votación.
- Un solo proyecto por contrato.
- No se verifica on-chain que el CID exista en IPFS.

## XIII. Roadmap

### Fase 2 – Funcionalidad
- Factory para desplegar un escrow por proyecto.
- Reembolso proporcional a donantes si un hito es rechazado o vence el plazo.
- Deadlines de votación y quórum configurable.
- Alta/baja de auditores mediante gobernanza (multisig o DAO).
- Donaciones en stablecoins (ERC-20 con `SafeERC20`).

### Fase 3 – Seguridad y escalabilidad
- Oráculo real (Chainlink Functions o red de validadores con firmas EIP-712) detrás de la misma interfaz.
- `Pausable` y timelock para operaciones críticas.
- Fuzzing e invariant testing ampliado; auditoría externa.
- Deploy en una L2 (Arbitrum/Base) para reducir costos de votación.
- Indexado de eventos con The Graph para el dashboard.

## XIV. Conclusión

Este proyecto demuestra cómo la tecnología *blockchain* puede mejorar la rendición de cuentas en la financiación pública y científica, transformando la gobernanza y la distribución de fondos en reglas transparentes y programables.
