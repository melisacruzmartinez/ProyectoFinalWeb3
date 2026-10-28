import { useCallback, useEffect, useMemo, useState } from 'react'
import { ethers } from 'ethers'
import './App.css'
import { CONTRACT_ADDRESS, NETWORK, SCIENTIFIC_FUND_ABI } from './contract'
import {
  decryptText,
  encryptText,
  parseEncrypted,
  serializeEncrypted,
} from './utils/crypto'

const milestones = [
  {
    id: 1,
    title: 'Diseño del protocolo y validación inicial',
    funding: '2 ETH',
    ipfs: 'QmA1...42f',
    status: 'Aprobado',
    votes: '3/3',
  },
  {
    id: 2,
    title: 'Pruebas de laboratorio y análisis estadístico',
    funding: '3 ETH',
    ipfs: 'QmB2...93c',
    status: 'Pendiente',
    votes: '2/3',
  },
  {
    id: 3,
    title: 'Publicación y difusión abierta de resultados',
    funding: '4 ETH',
    ipfs: 'QmC3...71a',
    status: 'En revisión',
    votes: '1/3',
  },
]

const auditors = ['Alice', 'Bob', 'Carol']

function App() {
  const [donation, setDonation] = useState('0.5')
  const [raised, setRaised] = useState('0')
  const [selected, setSelected] = useState(0)
  const [wallet, setWallet] = useState('')
  const [status, setStatus] = useState('MetaMask no conectado')
  const [isLoading, setIsLoading] = useState(false)
  const [contract, setContract] = useState(null)
  const [cryptoDemo, setCryptoDemo] = useState('')

  const secret = import.meta.env.VITE_CRYPTO_SECRET || 'demo-local-secret'
  const selectedMilestone = useMemo(() => milestones[selected], [selected])

  const refreshRaised = useCallback(async (contractInstance) => {
    if (!contractInstance) return

    try {
      const value = await contractInstance.totalRaised()
      setRaised(ethers.formatEther(value))
    } catch {
      setStatus('No se pudo leer la recaudación del contrato.')
    }
  }, [])

  const ensureLocalNetwork = useCallback(async () => {
    if (!window.ethereum) return

    try {
      await window.ethereum.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: NETWORK.chainIdHex }],
      })
    } catch (switchError) {
      if (switchError.code === 4902) {
        await window.ethereum.request({
          method: 'wallet_addEthereumChain',
          params: [
            {
              chainId: NETWORK.chainIdHex,
              chainName: NETWORK.chainName,
              nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
              rpcUrls: NETWORK.rpcUrls,
              blockExplorerUrls: NETWORK.blockExplorerUrls,
            },
          ],
        })
      }
    }
  }, [])

  const connectWallet = useCallback(async () => {
    if (!window.ethereum) {
      setStatus('Instala MetaMask para conectar tu cartera.')
      return
    }

    try {
      setIsLoading(true)
      const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' })
      await ensureLocalNetwork()
      const provider = new ethers.BrowserProvider(window.ethereum)
      const signer = await provider.getSigner()
      const contractInstance = new ethers.Contract(
        CONTRACT_ADDRESS,
        SCIENTIFIC_FUND_ABI,
        signer,
      )

      setWallet(accounts[0])
      setContract(contractInstance)
      await refreshRaised(contractInstance)
      setStatus('MetaMask conectado correctamente.')
    } catch (error) {
      setStatus(error.shortMessage || error.message || 'Error al conectar la cartera.')
    } finally {
      setIsLoading(false)
    }
  }, [ensureLocalNetwork, refreshRaised])

  useEffect(() => {
    const init = async () => {
      try {
        const readProvider = new ethers.JsonRpcProvider(NETWORK.rpcUrls[0])
        const network = await readProvider.getNetwork()
        if (network.chainId !== NETWORK.chainId) {
          setStatus(`No se pudo conectar a ${NETWORK.chainName}.`)
          return
        }

        const deployedCode = await readProvider.getCode(CONTRACT_ADDRESS)
        if (deployedCode === '0x') {
          setStatus(`No hay contrato en ${CONTRACT_ADDRESS} sobre ${NETWORK.chainName}.`)
          return
        }

        const readContract = new ethers.Contract(
          CONTRACT_ADDRESS,
          SCIENTIFIC_FUND_ABI,
          readProvider,
        )
        await refreshRaised(readContract)

        if (!window.ethereum) return

        const provider = new ethers.BrowserProvider(window.ethereum)
        const accounts = await provider.listAccounts()
        if (accounts.length > 0) {
          const signer = await provider.getSigner()
          const contractInstance = new ethers.Contract(
            CONTRACT_ADDRESS,
            SCIENTIFIC_FUND_ABI,
            signer,
          )
          setWallet(accounts[0].address)
          setContract(contractInstance)
          await refreshRaised(contractInstance)
          setStatus('MetaMask ya estaba conectado.')
        }
      } catch (error) {
        console.error(error)
        setStatus(error.shortMessage || error.message || 'No se pudo leer el contrato.')
      }
    }

    init()
  }, [refreshRaised])

  const handleDonate = async () => {
    if (!contract) {
      setStatus('Conecta MetaMask antes de donar.')
      return
    }

    let amountWei
    try {
      amountWei = ethers.parseEther(donation.trim())
    } catch {
      setStatus('Introduce una cantidad decimal válida (máximo 18 decimales).')
      return
    }

    if (amountWei <= 0n) {
      setStatus('Introduce una cantidad válida.')
      return
    }

    try {
      setIsLoading(true)
      const provider = new ethers.BrowserProvider(window.ethereum)
      const network = await provider.getNetwork()
      if (network.chainId !== NETWORK.chainId) {
        setStatus(`Selecciona ${NETWORK.chainName} (chain ID ${NETWORK.chainId}) en MetaMask.`)
        return
      }

      const deployedCode = await provider.getCode(CONTRACT_ADDRESS)
      if (deployedCode === '0x') {
        setStatus(`No hay contrato en ${CONTRACT_ADDRESS} sobre ${NETWORK.chainName}.`)
        return
      }

      const tx = await contract.contribute({ value: amountWei })
      setStatus('Transacción enviada. Esperando confirmación...')
      await tx.wait()
      await refreshRaised(contract)
      setStatus('Donación confirmada correctamente.')
    } catch (error) {
      setStatus(error.shortMessage || error.message || 'La transacción falló.')
    } finally {
      setIsLoading(false)
    }
  }

  const handleCryptoDemo = async () => {
    try {
      const plainText = `dato-sensible:${wallet || 'usuario-local'}`
      const encrypted = await encryptText(plainText, secret)
      const serialized = serializeEncrypted(encrypted)
      const decrypted = await decryptText(parseEncrypted(serialized), secret)
      setCryptoDemo(`Cifrado OK: ${decrypted}`)
    } catch (error) {
      setCryptoDemo(`Error de cifrado: ${error.message}`)
    }
  }

  return (
    <div className="app-shell">
      <header className="topbar">
        <div>
          <span className="eyebrow">Blockchain para ciencia</span>
          <h1>Scientific Fund DAO</h1>
        </div>
        <button type="button" className="primary-btn" onClick={connectWallet} disabled={isLoading}>
          {wallet ? `${wallet.slice(0, 6)}...${wallet.slice(-4)}` : 'Conectar MetaMask'}
        </button>
      </header>

      <main className="main-grid">
        <section className="hero-card">
          <div className="hero-copy">
            <p className="kicker">Financiación pública verificable</p>
            <h2>Trasparencia financiera para proyectos científicos con validación descentralizada.</h2>
            <p className="description">
              Los fondos se depositan en escrow, se revisan por hitos y solo se liberan si
              auditores independientes y validadores externos aprueban la evidencia.
            </p>
            <p className="status-text">{status}</p>
          </div>

          <div className="fund-box">
            <div className="stat-row">
              <span>Total recaudado</span>
              <strong>{Number(raised).toLocaleString('es-ES', { maximumFractionDigits: 4 })} ETH</strong>
            </div>
            <div className="stat-row">
              <span>Objetivo</span>
              <strong>200 ETH</strong>
            </div>
            <div className="stat-row progress-row">
              <span>Progreso</span>
              <strong>{Math.min((Number(raised) / 200) * 100, 100).toFixed(0)}%</strong>
            </div>
            <div className="progress-bar">
              <span style={{ width: `${Math.min((Number(raised) / 200) * 100, 100)}%` }} />
            </div>

            <div className="donate-box">
              <input
                type="number"
                min="0.01"
                step="0.01"
                value={donation}
                onChange={(event) => setDonation(event.target.value)}
              />
              <button type="button" onClick={handleDonate} disabled={isLoading}>
                {isLoading ? 'Procesando...' : 'Donar'}
              </button>
            </div>
          </div>
        </section>

        <section className="metrics-grid">
          <article className="metric-card">
            <span>Donantes</span>
            <strong>428</strong>
            <small>Comunidad abierta</small>
          </article>
          <article className="metric-card">
            <span>Auditores</span>
            <strong>3</strong>
            <small>Verificación independiente</small>
          </article>
          <article className="metric-card">
            <span>Hash IPFS</span>
            <strong>QmA1...</strong>
            <small>Pruebas inmutables</small>
          </article>
          <article className="metric-card">
            <span>Red</span>
            <strong>{NETWORK.chainName}</strong>
            <small>ETH de prueba</small>
          </article>
        </section>

        <section className="panel">
          <div className="panel-header">
            <h3>Hitos del proyecto</h3>
            <span>Escrow + validación</span>
          </div>

          <div className="milestone-list">
            {milestones.map((milestone, index) => (
              <button
                key={milestone.id}
                type="button"
                className={selected === index ? 'milestone active' : 'milestone'}
                onClick={() => setSelected(index)}
              >
                <span className="milestone-id">Hito {milestone.id}</span>
                <strong>{milestone.title}</strong>
                <small>{milestone.funding}</small>
              </button>
            ))}
          </div>

          <div className="milestone-detail">
            <div className="detail-top">
              <span className="badge">{selectedMilestone.status}</span>
              <span>{selectedMilestone.votes}</span>
            </div>
            <h4>{selectedMilestone.title}</h4>
            <p>
              IPFS: <strong>{selectedMilestone.ipfs}</strong>
            </p>
            <p>Monto comprometido: {selectedMilestone.funding}</p>
          </div>
        </section>

        <section className="panel audit-panel">
          <div className="panel-header">
            <h3>Panel de auditoría</h3>
            <span>Consenso requerido</span>
          </div>

          <ul className="audit-list">
            {auditors.map((auditor, index) => (
              <li key={auditor}>
                <span>{auditor}</span>
                <div className="vote-pill">
                  {index === 0 ? 'Aprobado' : index === 1 ? 'Pendiente' : 'Rechazado'}
                </div>
              </li>
            ))}
          </ul>
        </section>

        <section className="panel">
          <div className="panel-header">
            <h3>Ejemplo de cifrado local</h3>
            <span>Secreto desde VITE_CRYPTO_SECRET</span>
          </div>

          <button type="button" className="primary-btn" onClick={handleCryptoDemo}>
            Probar cifrado/descifrado
          </button>

          {cryptoDemo && <p className="status-text">{cryptoDemo}</p>}
        </section>
      </main>
    </div>
  )
}

export default App
