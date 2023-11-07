// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract CeloDao is Ownable, ReentrancyGuard {
    uint256 public totalProposals;
    uint256 public balance;
    address public deployer;

    uint256 immutable STAKEHOLDER_MIN_CONTRIBUTION = 0.1 ether;
    uint256 immutable MIN_VOTE_PERIOD = 5 minutes;

    bytes32 private immutable COLLABORATOR_ROLE = keccak256("collaborator");
    bytes32 private immutable STAKEHOLDER_ROLE = keccak256("stakeholder");

    struct Proposals {
        uint256 id;
        uint256 amount;
        uint256 upVote;
        uint256 downVotes;
        uint256 duration;
        string title;
        string description;
        bool paid;
        bool passed;
        address payable beneficiary;
        address propoper;
        address executor;
    }

    struct Voted {
        address voter;
        uint256 timestamp;
        bool chosen;
    }

    mapping(uint256 => Proposals) private raisedProposals;
    mapping(address => uint256[]) private stakeholderVotes;
    mapping(uint256 => Voted[]) private votedOn;
    mapping(address => uint256) private contributors;
    mapping(address => uint256) private stakeholders;

    modifier stakeholderOnly() {
        require(hasRole(STAKEHOLDER_ROLE, msg.sender), "Only stakeholders are allowed to create Proposals");
        _;
    }

    modifier contributorOnly() {
        require(hasRole(COLLABORATOR_ROLE, msg.sender), "Only collaborators are allowed");
        _;
    }

    event ProposalAction(
        address indexed creator,
        bytes32 role,
        string message,
        address indexed beneficiary,
        uint256 amount
    );

    event VoteAction(
        address indexed creator,
        bytes32 role,
        string message,
        address indexed beneficiary,
        uint256 amount,
        uint256 upVote,
        uint256 downVotes,
        bool chosen
    );

    constructor() {
        deployer = msg.sender;
    }

    function createProposal(
        string calldata title,
        string calldata description,
        address beneficiary,
        uint256 amount
    ) external stakeholderOnly returns (Proposals memory) {
        uint256 currentID = totalProposals++;
        Proposals storage stakeholderProposal = raisedProposals[currentID];
        stakeholderProposal.id = currentID;
        stakeholderProposal.amount = amount;
        stakeholderProposal.title = title;
        stakeholderProposal.description = description;
        stakeholderProposal.beneficiary = payable(beneficiary);
        stakeholderProposal.duration = block.timestamp + MIN_VOTE_PERIOD;

        emit ProposalAction(msg.sender, STAKEHOLDER_ROLE, 'Proposal Raised', beneficiary, amount);
        return stakeholderProposal;
    }

    function performVote(uint256 proposalId, bool chosen) external stakeholderOnly returns (Voted memory) {
        Proposals storage stakeholderProposal = raisedProposals[proposalId];
        require(!stakeholderProposal.passed && stakeholderProposal.duration > block.timestamp, "Proposal is not open for voting");
        handleVoting(proposalId);

        if (chosen) {
            stakeholderProposal.upVote++;
        } else {
            stakeholderProposal.downVotes++;
        }

        stakeholderVotes[msg.sender].push(proposalId);
        votedOn[proposalId].push(Voted(msg.sender, block.timestamp, chosen));

        emit VoteAction(msg.sender, STAKEHOLDER_ROLE, "PROPOSAL VOTE", stakeholderProposal.beneficiary, stakeholderProposal.amount, stakeholderProposal.upVote, stakeholderProposal.downVotes, chosen);

        return Voted(msg.sender, block.timestamp, chosen);
    }

    function handleVoting(uint256 proposalId) private {
        uint256[] memory tempVotes = stakeholderVotes[msg.sender];
        for (uint256 vote = 0; vote < tempVotes.length; vote++) {
            if (proposalId == tempVotes[vote]) {
                revert("Double voting is not allowed");
            }
        }
    }

    function payBeneficiary(uint proposalId) external nonReentrant onlyOwner returns (uint256) {
        Proposals storage stakeholderProposal = raisedProposals[proposalId];
        require(balance >= stakeholderProposal.amount, "Insufficient fund");
        require(!stakeholderProposal.paid, "Payment already made");
        require(stakeholderProposal.upVote > stakeholderProposal.downVotes, "Insufficient votes");

        pay(stakeholderProposal.amount, stakeholderProposal.beneficiary);
        stakeholderProposal.paid = true;
        stakeholderProposal.executor = msg.sender;
        balance -= stakeholderProposal.amount;

        emit ProposalAction(msg.sender, STAKEHOLDER_ROLE, "PAYMENT SUCCESSFULLY MADE!", stakeholderProposal.beneficiary, stakeholderProposal.amount);

        return balance;
    }

    function pay(uint256 amount, address to) internal returns (bool) {
        (bool success, ) = payable(to).call{value: amount}("");
        require(success, "Payment failed");
        return true;
    }

    function contribute() external payable {
        require(msg.value > 0 ether, "Invalid amount");
        uint256 totalContributions = contributors[msg.sender] + msg.value;

        if (!hasRole(STAKEHOLDER_ROLE, msg.sender)) {
            if (totalContributions >= STAKEHOLDER_MIN_CONTRIBUTION) {
                stakeholders[msg.sender] = msg.value;
                contributors[msg.sender] += msg.value;
                grantRole(STAKEHOLDER_ROLE, msg.sender);
            } else {
                contributors[msg.sender] += msg.value;
                grantRole(COLLABORATOR_ROLE, msg.sender);
            }
        } else {
            stakeholders[msg.sender] += msg.value;
            contributors[msg.sender] += msg.value;
        }

        balance += msg.value;
        emit ProposalAction(msg.sender, STAKEHOLDER_ROLE, "CONTRIBUTION SUCCESSFULLY RECEIVED!", address(this), msg.value);
    }

    function getProposals(uint256 proposalID) external view returns (Proposals memory) {
        return raisedProposals[proposalID];
    }

    function getAllProposals() external view returns (Proposals[] memory props) {
        props = new Proposals[](totalProposals);
        for (uint i = 0; i < totalProposals; i++) {
            props[i] = raisedProposals[i];
        }
    }

    function getProposalVote(uint256 proposalID) external view returns (Voted[] memory) {
        return votedOn[proposalID];
    }

    function getStakeholdersVotes() external view returns (uint256[] memory) {
        return stakeholderVotes[msg.sender];
    }

    function getStakeholdersBalances() external view returns (uint256) {
        return stakeholders[msg.sender];
    }

    function getTotalBalance() external view returns (uint256) {
        return balance;
    }

    function isStakeholder() external view returns (bool) {
        return stakeholders[msg.sender] > 0;
    }

    function isContributor() external view returns (bool) {
        return contributors[msg.sender] > 0;
    }

    function getContributorsBalance() external view returns (uint256) {
        return contributors[msg.sender];
    }

    function getDeployer() external view returns (address) {
        return deployer;
    }
}
