export const CONTRACT_ADDRESS = '0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512'

export const SCIENTIFIC_FUND_ABI = [
  'function contribute() payable',
  'function totalRaised() view returns (uint256)',
  'function milestoneCount() view returns (uint256)',
  'function createMilestone(string memory title, string memory ipfsHash, uint256 amount) external',
  'function voteMilestone(uint256 milestoneId, bool support) external',
  'function releaseMilestone(uint256 milestoneId) external',
  'function owner() view returns (address)',
  'function isMilestoneReleased(uint256 milestoneId) view returns (bool)',
  'event Contribution(address indexed donor, uint256 amount, uint256 totalRaised_)',
]
