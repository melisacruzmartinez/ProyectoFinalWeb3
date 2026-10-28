// Red objetivo: 'sepolia' (default) o 'anvil' (demo local). Se elige con VITE_NETWORK en frontend/.env
const NETWORKS = {
  sepolia: {
    chainId: 11155111n,
    chainIdHex: '0xaa36a7',
    chainName: 'Sepolia',
    rpcUrls: ['https://ethereum-sepolia-rpc.publicnode.com'],
    blockExplorerUrls: ['https://sepolia.etherscan.io'],
    contractAddress: '0x5495219693ACbD985C1e375f5405B81995849149',
  },
  anvil: {
    chainId: 31337n,
    chainIdHex: '0x7a69',
    chainName: 'Anvil Local',
    rpcUrls: ['http://127.0.0.1:8545'],
    blockExplorerUrls: [],
    contractAddress: '0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512',
  },
}

export const NETWORK = NETWORKS[import.meta.env.VITE_NETWORK || 'sepolia'] ?? NETWORKS.sepolia
export const CONTRACT_ADDRESS = NETWORK.contractAddress

export const SCIENTIFIC_FUND_ABI = [
  'function contribute() payable',
  'function totalRaised() view returns (uint256)',
  'function milestoneCount() view returns (uint256)',
  'function createMilestone(string title, string ipfsHash, uint256 amount) returns (uint256)',
  'function voteMilestone(uint256 milestoneId, bool support)',
  'function validateMilestone(uint256 milestoneId) returns (bool)',
  'function releaseMilestone(uint256 milestoneId)',
  'function owner() view returns (address)',
  'function isMilestoneReleased(uint256 milestoneId) view returns (bool)',
  'event Contribution(address indexed donor, uint256 amount, uint256 totalRaised)',
]
