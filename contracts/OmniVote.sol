// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";

contract OmniVote is CCIPReceiver, OwnerIsCreator {
  using SafeERC20 for IERC20;

  struct Proposal {
    string description;
    uint256 startTime;
    uint256 endTime;
    uint256 quorum;
    mapping(address => uint256) votes;
    uint256 totalVotes;
  }

  mapping(bytes32 => Proposal) public proposals;
  mapping(address => bool) public whitelistedUsers;

  uint256 public creationFee;

  event ProposalCreated(
    bytes32 indexed proposalId,
    string description,
    uint256 startTime,
    uint256 endTime,
    uint256 quorum
  );
  event VoteSubmitted(address indexed voter, bytes32 indexed proposalId, uint256 weight);
  event CrossChainProposalCreated(bytes32 indexed proposalId, string description, uint16 destinationChainId);
  event CrossChainVoteSubmitted(bytes32 indexed proposalId, uint16 destinationChainId);
  event ProposalFinalized(bytes32 indexed proposalId);

  IRouterClient public router;
  IERC20 private s_linkToken;

  constructor(address _router, address _link, uint256 _creationFee) CCIPReceiver(_router) {
    router = IRouterClient(_router);
    s_linkToken = IERC20(_link);
    creationFee = _creationFee;
  }

  // On-Chain Proposal Creation with Fee
  function createProposal(
    bytes32 _proposalId,
    string calldata _description,
    uint256 _startTime,
    uint256 _endTime,
    uint256 _quorum
  ) external payable {
    require(msg.value >= creationFee, "Insufficient fee for proposal creation");
    require(proposals[_proposalId].startTime == 0, "Proposal already exists");

    Proposal storage proposal = proposals[_proposalId];
    proposal.description = _description;
    proposal.startTime = _startTime;
    proposal.endTime = _endTime;
    proposal.quorum = _quorum;

    emit ProposalCreated(_proposalId, _description, _startTime, _endTime, _quorum);
  }

  // Cross-Chain Proposal Creation with Fee
  function createCrossChainProposal(
    bytes32 _proposalId,
    string calldata _description,
    uint256 _startTime,
    uint256 _endTime,
    uint256 _quorum,
    uint16 destinationChainId,
    bytes memory receiverAddress
  ) external payable {
    require(msg.value >= creationFee, "Insufficient fee for proposal creation");

    bytes memory payload = abi.encode(_proposalId, _description, _startTime, _endTime, _quorum);

    router.send(destinationChainId, receiverAddress, payload);

    emit CrossChainProposalCreated(_proposalId, _description, destinationChainId);
  }

  // On-Chain Voting
  function submitVote(bytes32 _proposalId, uint256 _weight) external {
    require(whitelistedUsers[msg.sender], "User not whitelisted");
    Proposal storage proposal = proposals[_proposalId];
    require(block.timestamp >= proposal.startTime && block.timestamp <= proposal.endTime, "Voting not active");

    proposal.votes[msg.sender] += _weight;
    proposal.totalVotes += _weight;

    emit VoteSubmitted(msg.sender, _proposalId, _weight);
  }

  // Cross-Chain Voting
  function submitCrossChainVote(
    bytes32 _proposalId,
    uint256 _weight,
    uint16 destinationChainId,
    bytes memory receiverAddress
  ) external {
    require(whitelistedUsers[msg.sender], "User not whitelisted");
    Proposal storage proposal = proposals[_proposalId];
    require(block.timestamp >= proposal.startTime && block.timestamp <= proposal.endTime, "Voting not active");

    bytes memory payload = abi.encode(_proposalId, _weight, msg.sender);

    router.send(destinationChainId, receiverAddress, payload);

    emit CrossChainVoteSubmitted(_proposalId, destinationChainId);
  }

  // On-Chain Proposal Finalization
  function finalizeProposal(bytes32 _proposalId) external onlyOwner {
    Proposal storage proposal = proposals[_proposalId];
    require(block.timestamp > proposal.endTime, "Voting period not yet ended");
    emit ProposalFinalized(_proposalId);
  }

  // Cross-Chain Proposal Finalization
  function finalizeCrossChainProposal(
    bytes32 _proposalId,
    uint16 destinationChainId,
    bytes memory receiverAddress
  ) external onlyOwner {
    bytes memory payload = abi.encode(_proposalId, "finalize");

    router.send(destinationChainId, receiverAddress, payload);

    emit ProposalFinalized(_proposalId);
  }

  // Handle incoming CCIP messages
  function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) internal override {
    // Example: handle proposal creation or voting based on incoming message
    (bytes32 proposalId, uint256 weight, address voter) = abi.decode(any2EvmMessage.data, (bytes32, uint256, address));
    if (weight > 0) {
      // This is a vote
      Proposal storage proposal = proposals[proposalId];
      proposal.votes[voter] += weight;
      proposal.totalVotes += weight;
      emit VoteSubmitted(voter, proposalId, weight);
    } else {
      // Other actions like proposal creation
      // Decode and handle accordingly
    }
  }

  // On-Chain Retrieval of Proposal Details
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

  // Cross-Chain Retrieval of Proposal Details (Simulation, would be handled by a message to another chain)
  function getCrossChainProposalDetails(
    bytes32 _proposalId,
    uint16 destinationChainId,
    bytes memory receiverAddress
  ) external onlyOwner {
    bytes memory payload = abi.encode(_proposalId, "getDetails");

    router.send(destinationChainId, receiverAddress, payload);
  }

  // On-Chain Retrieval of All Votes
  function getAllVotes(bytes32 _proposalId) external view returns (uint256 totalVotes) {
    return proposals[_proposalId].totalVotes;
  }

  // Cross-Chain Retrieval of All Votes (Simulation, would be handled by a message to another chain)
  function getCrossChainAllVotes(
    bytes32 _proposalId,
    uint16 destinationChainId,
    bytes memory receiverAddress
  ) external onlyOwner {
    bytes memory payload = abi.encode(_proposalId, "getVotes");

    router.send(destinationChainId, receiverAddress, payload);
  }

  // Allow the owner to withdraw the proposal creation fees
  function withdrawFees() external onlyOwner {
    payable(owner()).transfer(address(this).balance);
  }
}
