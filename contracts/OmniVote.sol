// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";

contract OmniVote is CCIPReceiver, OwnerIsCreator {
  using ECDSA for bytes32;

  uint256 public creationFee;
  struct DAOInfo {
    address daoAddress;
    string name;
    string description;
    string ipfsMetadataHash;
    address tokenAddress;
    uint256 minimumTokens;
  }

  struct Proposal {
    string description;
    uint256 startTime;
    uint256 endTime;
    uint256 quorum;
    mapping(address => uint256) votes;
    uint256 totalVotes;
  }

  mapping(bytes32 => DAOInfo) public daos;
  mapping(bytes32 => Proposal) public proposals;
  mapping(address => bool) public whitelistedUsers;

  event CreationFeeUpdated(uint256 newFee);
  event DaoAdded(bytes32 indexed daoId, address indexed daoCreator, string name, string description);

  event MinimumTokensUpdated(bytes32 indexed daoId, uint256 newMinimum);
  event ProposalCreated(
    bytes32 indexed daoId,
    bytes32 indexed proposalId,
    string description,
    uint256 startTime,
    uint256 endTime,
    uint256 quorum
  );
  event VoteSubmitted(address indexed voter, bytes32 indexed proposalId, uint256 weight);
  event ProposalFinalized(bytes32 indexed proposalId);

  constructor(address _router, address link, uint256 initialCreationFee) CCIPReceiver(_router) {
    // linkToken = LinkTokenInterface(link);
    // usdcToken = new MockUSDC();
    creationFee = initialCreationFee; // Set the initial creation fee
  }

  function setCreationFee(uint256 newFee) external onlyOwner {
    creationFee = newFee;
    emit CreationFeeUpdated(newFee);
  }

  function addDao(
    bytes32 _daoId,
    string memory _name,
    string memory _description,
    string memory _ipfsMetadataHash,
    address _tokenAddress,
    uint256 _minimumTokens
  ) public payable {
    require(msg.value >= creationFee, "Creation fee not met");
    require(daos[_daoId].daoAddress == address(0), "DAO ID already in use");

    // DAO creation logic
    daos[_daoId] = DAOInfo({
      daoAddress: msg.sender,
      name: _name,
      description: _description,
      ipfsMetadataHash: _ipfsMetadataHash,
      tokenAddress: _tokenAddress,
      minimumTokens: _minimumTokens
    });
    emit DaoAdded(_daoId, msg.sender, _name, _description);
  }

  function updateMinimumTokens(bytes32 _daoId, uint256 _newMinimum) external {
    require(msg.sender == daos[_daoId].daoAddress, "Unauthorized");
    daos[_daoId].minimumTokens = _newMinimum;
    emit MinimumTokensUpdated(_daoId, _newMinimum);
  }

  function createProposal(
    bytes32 _daoId,
    bytes32 _proposalId,
    string calldata _description,
    uint256 _startTime,
    uint256 _endTime,
    uint256 _quorum
  ) external {
    require(msg.sender == daos[_daoId].daoAddress, "Unauthorized");
    require(daos[_daoId].daoAddress != address(0), "DAO does not exist");
    require(proposals[_proposalId].startTime == 0, "Proposal already exists"); // Ensuring not to overwrite existing proposal
    // Initialize each field of the struct individually
    Proposal storage proposal = proposals[_proposalId];
    proposal.description = _description;
    proposal.startTime = _startTime;
    proposal.endTime = _endTime;
    proposal.quorum = _quorum;

    emit ProposalCreated(_daoId, _proposalId, _description, _startTime, _endTime, _quorum);
  }

  function submitVote(bytes32 _proposalId, uint256 _weight) external {
    require(whitelistedUsers[msg.sender], "User not whitelisted");
    Proposal storage proposal = proposals[_proposalId];
    require(block.timestamp >= proposal.startTime && block.timestamp <= proposal.endTime, "Voting not active");

    bytes32 daoId = findDaoIdByProposal(_proposalId);
    require(IERC20(daos[daoId].tokenAddress).balanceOf(msg.sender) >= daos[daoId].minimumTokens, "Insufficient tokens");

    proposal.votes[msg.sender] += _weight;
    proposal.totalVotes += _weight;
    emit VoteSubmitted(msg.sender, _proposalId, _weight);
  }

  function finalizeProposal(bytes32 _proposalId) external {
    bytes32 daoId = findDaoIdByProposal(_proposalId);
    require(msg.sender == daos[daoId].daoAddress, "Unauthorized");
    Proposal storage proposal = proposals[_proposalId];
    require(block.timestamp > proposal.endTime, "Voting period not yet ended");
    emit ProposalFinalized(_proposalId);
  }

  function getProposalDetails(
    bytes32 _proposalId
  )
    external
    view
    returns (string memory description, uint256 startTime, uint256 endTime, uint256 quorum, uint256 totalVotes)
  {
    Proposal storage proposal = proposals[_proposalId];
    return (proposal.description, proposal.startTime, proposal.endTime, proposal.quorum, proposal.totalVotes);
  }

  // Utility function to find the DAO ID from a proposal ID
  function findDaoIdByProposal(bytes32 _proposalId) private view returns (bytes32) {
    // Simplified; assume DAO ID is directly obtainable or derive logic to map it correctly
    return bytes32(0); // Placeholder logic
  }
}
