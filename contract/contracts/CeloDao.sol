// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract CeloDao is AccessControl, ReentrancyGuard {

    uint256 totalProposals;
    uint256 balance;
    address deployer;

    uint256 immutable STAKEHOLDER_MIN_CONTRIBUTION = 0.1 ether;
    uint256 immutable MIN_VOTE_PERIOD = 5 minutes;
    bytes32 private immutable COLLABORATOR_ROLE = keccak256("collaborator");
    bytes32 private immutable STAKEHOLDER_ROLE = keccak256("stakeholder");

    mapping(uint256 => Proposals) private raisedProposals;
    mapping(address => uint256[]) private stakeholderVotes;
    mapping(uint256 => Voted[]) private votedOn;
    mapping(address => uint256) private contributors;
    mapping(address => uint256) private stakeholders;
    mapping(address => mapping(uint256 => bool)) private hasVoted;

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

    modifier stakeholderOnly(string memory message) {
        require(hasRole(STAKEHOLDER_ROLE, msg.sender), message);
        _;
    }

    modifier contributorOnly(string memory message) {
        require(hasRole(COLLABORATOR_ROLE, msg.sender), message);
        _;
    }

    modifier onlyDeployer(string memory message) {
        require(msg.sender == deployer, message);
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
    ) external stakeholderOnly("Only stakeholders are allowed to create Proposals") returns (Proposals memory) {
        require(balance + amount >= balance, "Proposal amount causes overflow");
        uint256 currentID = totalProposals++;
        Proposals storage StakeholderProposal = raisedProposals[currentID];
        StakeholderProposal.id = currentID;
        StakeholderProposal.amount = amount;
        StakeholderProposal.title = title;
        StakeholderProposal.description = description;
        StakeholderProposal.beneficiary = payable(beneficiary);
        StakeholderProposal.duration = block.timestamp + MIN_VOTE_PERIOD;

        emit ProposalAction(
            msg.sender,
            STAKEHOLDER_ROLE,
            'Proposal Raised',
            beneficiary,
            amount
        );

        return StakeholderProposal;
    }

    function performVote(uint256 proposalId, bool chosen) external
    stakeholderOnly("Only stakeholders can perform voting")
    returns (Voted memory)
    {
        require(proposalId < totalProposals, "Invalid proposal ID");
        require(!hasVoted[msg.sender][proposalId], "Stakeholder has already voted on this proposal");

        Proposals storage StakeholderProposal = raisedProposals[proposalId];
        require(!StakeholderProposal.passed && StakeholderProposal.duration > block.timestamp, "Proposal cannot be voted on");

        if (chosen) {
            StakeholderProposal.upVote++;
        } else {
            StakeholderProposal.downVotes++;
        }

        stakeholderVotes[msg.sender].push(proposalId);
        votedOn[proposalId].push(
            Voted(
                msg.sender,
                block.timestamp,
                chosen
            )
        );

        hasVoted[msg.sender][proposalId] = true;

        emit VoteAction(
            msg.sender,
            STAKEHOLDER_ROLE,
            "PROPOSAL VOTE",
            StakeholderProposal.beneficiary,
            StakeholderProposal.amount,
            StakeholderProposal.upVote,
            StakeholderProposal.downVotes,
            chosen
        );

        return Voted(
            msg.sender,
            block.timestamp,
            chosen
        );
    }

    function payBeneficiary(uint proposalId) external
    stakeholderOnly("Only stakeholders can make payment") onlyDeployer("Only deployer can make payment") nonReentrant() returns (uint256) {
        require(proposalId < totalProposals, "Invalid proposal ID");
        Proposals storage stakeholderProposal = raisedProposals[proposalId];
        require(balance >= stakeholderProposal.amount, "Insufficient fund");
        require(!stakeholderProposal.paid, "Payment already made");
        require(stakeholderProposal.upVote > stakeholderProposal.downVotes, "Insufficient votes");

        pay(stakeholderProposal.amount, stakeholderProposal.beneficiary);
        stakeholderProposal.paid = true;
        stakeholderProposal.executor = msg.sender;
        balance -= stakeholderProposal.amount;

        emit ProposalAction(
            msg.sender,
            STAKEHOLDER_ROLE,
            "PAYMENT SUCCESSFULLY MADE!",
            stakeholderProposal.beneficiary,
            stakeholderProposal.amount
        );

        return balance;
    }

    function pay(uint256 amount, address to) internal returns (bool) {
        (bool success, ) = payable(to).call{value: amount}("");
        require(success, "Payment failed");
        return true;
    }

    function contribute() payable external returns (uint256) {
        require(msg.value > 0 ether, "Invalid amount");
        uint256 totalContributions = contributors[msg.sender] + msg.value;

        if (!hasRole(STAKEHOLDER_ROLE, msg.sender)) {
            if (totalContributions >= STAKEHOLDER_MIN_CONTRIBUTION) {
                stakeholders[msg.sender] = msg.value;
                _setupRole(STAKEHOLDER_ROLE, msg.sender);
                _setupRole(COLLABORATOR_ROLE, msg.sender);
            } else {
                contributors[msg.sender] += msg.value;
                _setupRole(COLLABORATOR_ROLE, msg.sender);
            }
        } else {
            stakeholders[msg.sender] += msg.value;
        }

        balance += msg.value;
        emit ProposalAction(
            msg.sender,
            STAKEHOLDER_ROLE,
            "CONTRIBUTION SUCCESSFULLY RECEIVED!",
            address(this),
            msg.value
        );

        return balance;
    }

    function getProposals(uint256 proposalID) external view returns (Proposals memory) {
        require(proposalID < totalProposals, "Invalid proposal ID");
        return raisedProposals[proposalID];
    }

    function getAllProposals() external view returns (Proposals[] memory props) {
        props = new Proposals[](totalProposals);
        for (uint i = 0; i < totalProposals; i++) {
            props[i] = raisedProposals[i];
        }
    }

    function getProposalVote(uint256 proposalID) external view returns (Voted[] memory) {
        require(proposalID < totalProposals, "Invalid proposal ID");
        return votedOn[proposalID];
    }

    function getStakeholdersVotes() stakeholderOnly("Unauthorized") external view returns (uint256[] memory) {
        return stakeholderVotes[msg.sender];
    }

    function getStakeholdersBalances() stakeholderOnly("Unauthorized") external view returns (uint256) {
        return stakeholders[msg.sender];
    }

    function getTotalBalance() external view returns (uint256) {
        return balance;
    }

    function stakeholderStatus() external view returns (bool) {
        return stakeholders[msg.sender] > 0;
    }

    function isContributor() external view returns (bool) {
        return contributors[msg.sender] > 0;
    }

    function getContributorsBalance() contributorOnly("Unauthorized") external view returns (uint256) {
        return contributors[msg.sender];
    }

    function getDeployer() external view returns (address) {
        return deployer;
    }
}
