// SPDX-License-Identifier : UNLICENSED
pragma solidity ^0.8.9;


import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title CeloDao - A Decentralized Autonomous Organization (DAO) Smart Contract
 * @dev This contract implements a DAO where stakeholders can create, vote on, and execute proposals.
 * Stakeholders are required to make a minimum contribution to participate in the DAO.
 * Contributors and stakeholders can propose, vote on, and execute proposals.
 * The contract also provides balance tracking and role management.
 */

contract CeloDao is AccessControl,ReentrancyGuard {

    /* State variables and roles */
    uint256 totalProposals;
    uint256 balance;
    address deployer;

    /* Constants and role definitions */
    uint256 immutable STAKEHOLDER_MIN_CONTRIBUTION = 0.1;
    uint256 immutable MIN_VOTE_PERIOD = 5 minutes;
    bytes32 private immutable COLLABORATOR_ROLE = keccak256("collaborator");
    bytes32 private immutable STAKEHOLDER_ROLE = keccak256("stakeholder");

    mapping(uint256 => Proposals) private raisedProposals;
    mapping(address => uint256[]) private stakeholderVotes;
    mapping(uint256 => Voted[]) private votedOn;
    mapping(address => uint256) private contributors;
    mapping(address => uint256) private stakeholders;

    /* Struct representing a proposal */
    struct Proposals {
        uint256 id;              /* Proposal ID. */
        uint256 amount;          /* Amount requested in the proposal. */
        uint256 upVote;          /* Number of upvotes received by the proposal. */
        uint256 downVotes;       /* Number of downvotes received by the proposal. */
        uint256 duration;        /* Proposal's duration in seconds. */
        string title;            /* Title of the proposal. */
        string description;      /* Description of the proposal. */
        bool paid;               /* Flag indicating if the proposal has been paid. */
        bool passed;             /* Flag indicating if the proposal has passed. */
        address payable beneficiary; /* Address of the proposal beneficiary. */
        address propoper;        /* Address of the proposer of the proposal. */
        address executor;        /* Address of the proposal executor. */
    }

    /* Struct representing a vote */
    struct Voted {
        address voter;        /* Address of the voter. */
        uint256 timestamp;    /* Timestamp of the vote. */
        bool chosen;          /* Flag indicating the choice made in the vote. */
    }

    /**
     * @dev Modifier to restrict access to stakeholders only.
     * @param message Error message to display if access is denied.
     */
     modifier stakeholderOnly(string memory message) {
        require(hasRole(STAKEHOLDER_ROLE, msg.sender), "Stakeholder access only: " . concat(message));
        _;
    }

    /**
     * @dev Modifier to restrict access to contributors only.
     * @param message Error message to display if access is denied.
     */
    modifier contributorOnly(string memory message) {
        require(hasRole(COLLABORATOR_ROLE, msg.sender), "Contributor access only: " . concat(message));
        _;
    }

    /**
     * @dev Helper function to concatenate two strings.
     * @param a First string to concatenate.
     * @param b Second string to concatenate.
     * @return Concatenated string.
     */
    function concat(string memory a, string memory b) internal pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }

    /**
     * @dev Modifier to restrict access to the deployer only.
     * @param message Error message to display if access is denied.
     */
    modifier onlyDeployer(string memory message) {
        require(msg.sender == deployer,message);

        _;
    }

    /**
     * @dev Emitted when a proposal-related action occurs, such as proposal creation, voting, or payment.
     *
     * @param creator The address of the user who triggered the action.
     * @param role The role (STAKEHOLDER_ROLE or COLLABORATOR_ROLE) of the user who triggered the action.
     * @param message A descriptive message providing details about the action.
     * @param beneficiary The address of the beneficiary related to the action (e.g., proposal creator or recipient of payment).
     * @param amount The amount associated with the action (e.g., proposal amount or payment amount).
     */
    event ProposalAction(
        address indexed creator,
        bytes32 role,
        string message,
        address indexed beneficiary,
        uint256 amount
    );


    /**
     * @dev Emitted when a voting-related action occurs, such as voting on a proposal.
     *
     * @param creator The address of the user who cast the vote.
     * @param role The role (STAKEHOLDER_ROLE or COLLABORATOR_ROLE) of the user who cast the vote.
     * @param message A descriptive message providing details about the vote action.
     * @param beneficiary The address of the beneficiary associated with the vote action.
     * @param amount The amount associated with the vote action.
     * @param upVote The number of upvotes received for the proposal.
     * @param downVotes The number of downvotes received for the proposal.
     * @param chosen A boolean flag indicating whether the vote was in favor (chosen = true) or against (chosen = false).
     */
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


    /**
    * @dev Constructor to initialize the CeloDao contract.
    * It sets the deployer of the contract to the sender of the transaction.
    */
    constructor() public {
        deployer = msg.sender;
    }

    /**
    * @notice Creates a new proposal within the CeloDao contract.
    * @dev Only stakeholders are allowed to create proposals.
    * @param title The title of the proposal.
    * @param description The description of the proposal.
    * @param beneficiary The address of the proposal's beneficiary.
    * @param amount The amount of the proposal.
    * @return New proposal details including its ID.
    * @dev The function requires that:
    * - Sufficient contract balance covers the proposal amount.
    * - The title and description are not empty strings.
    * - The proposal amount is greater than or equal to the minimum contribution.
    * - The beneficiary address is not the zero address.
    * Upon successful creation, an event is emitted to record the action.
    */
    function createProposal (
        string calldata title,
        string calldata description,
        address beneficiary,
        uint256 amount
    ) external stakeholderOnly("Only stakeholders are allowed to create Proposals") returns(Proposals memory){
        require(balance >= amount, "Insufficient contract balance to create the proposal");
        require(bytes(title).length > 0, "Title cannot be empty");
        require(bytes(description).length > 0, "Description cannot be empty");
        require(amount >= STAKEHOLDER_MIN_CONTRIBUTION, "Proposal amount must be greater than or equal to the minimum contribution");
        require(beneficiary != address(0), "Invalid beneficiary address");

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


    
    /**
    * @notice Allows stakeholders to vote on a proposal within the CeloDao contract.
    * @dev Only stakeholders can perform voting, and the proposal must meet specific criteria.
    * @param proposalId The ID of the proposal to vote on.
    * @param chosen Indicates whether the stakeholder is voting in favor (true) or against (false) the proposal.
    * @return Details of the vote, including the voter, timestamp, and chosen option.
    * @dev The function requires that:
    * - The proposal ID is within the valid range.
    * - The proposal has not been paid yet.
    * The function records the stakeholder's vote, updates the proposal's vote counts, and emits a voting event.
    */
    function performVote(uint256 proposalId, bool chosen) external stakeholderOnly("Only stakeholders can perform voting") returns(Voted memory) {
        require(proposalId < totalProposals, "Invalid proposal ID"); // Check if proposalId is within the valid range
        require(!raisedProposals[proposalId].paid, "Proposal has already been paid"); // Check if the proposal has not been paid

        Proposals storage StakeholderProposal = raisedProposals[proposalId];
        handleVoting(StakeholderProposal);

        if (chosen) {
            StakeholderProposal.upVote++;
        } else {
            StakeholderProposal.downVotes++;
        }

        stakeholderVotes[msg.sender].push(StakeholderProposal.id);
        votedOn[StakeholderProposal.id].push(
            Voted(
                msg.sender,
                block.timestamp,
                chosen
            )
        );

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


    /**
    * @notice Handles the validation of stakeholder voting for a proposal.
    * @param proposal The proposal for which voting is being handled.
    * @dev This function ensures that the stakeholder's vote meets specific criteria:
    * - The proposal has not already passed or its duration has not expired.
    * - The stakeholder has not voted on the same proposal twice.
    * If any of these conditions are not met, the function will revert with an appropriate error message.
    */
    function handleVoting(Proposals storage proposal) private {
        if (proposal.passed || proposal.duration <= block.timestamp) {
            proposal.passed = true;
            revert("Time has already passed");
        }
        uint256[] memory tempVotes = stakeholderVotes[msg.sender];
        for (uint256 vote = 0; vote < tempVotes.length; vote++) {
            if (proposal.id == tempVotes[vote])
                revert("double voting is not allowed");
        }

    }

    /**
    * @notice Pay the beneficiary of a proposal after it has passed the voting period.
    * @param proposalId The unique identifier of the proposal to be paid.
    * @return The updated contract balance after the payment.
    * @dev This function allows only stakeholders, and the deployer, to initiate payments to beneficiaries of proposals. 
    * The proposal's balance must be sufficient, and the proposal must have received enough upvotes to be eligible for payment.
    * If any of these conditions are not met, the function will revert with an appropriate error message.
    * @param proposalId The unique identifier of the proposal to be paid.
    */
    function payBeneficiary(uint proposalId) external
    stakeholderOnly("Only stakeholders can make payment") onlyDeployer("Only deployer can make payment") nonReentrant() returns(uint256){
        Proposals storage stakeholderProposal = raisedProposals[proposalId];
        require(balance >= stakeholderProposal.amount, "insufficient fund");
        if(stakeholderProposal.paid == true) revert("payment already made");
        if(stakeholderProposal.upVote <= stakeholderProposal.downVotes) revert("insufficient votes");

        pay(stakeholderProposal.amount,stakeholderProposal.beneficiary);
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

    /**
    * @notice Perform a payment to a specified recipient.
    * @param amount The amount of Ether to be sent in the payment.
    * @param to The recipient's Ethereum address.
    * @return A boolean indicating the success of the payment.
    * @dev This internal function is used to send a specified amount of Ether to a designated recipient address. 
    * It ensures the success of the payment and reverts with an error message if the payment fails.
    * @param amount The amount of Ether to be sent in the payment.
    * @param to The recipient's Ethereum address.
    * @return A boolean indicating the success of the payment.
    */
    function pay(uint256 amount,address to) internal returns(bool){
        (bool success,) = payable(to).call{value : amount}("");
        require(success, "payment failed");
        return true;
    }

    /**
    * @notice Contribute funds to the contract.
    * @dev Allows an Ethereum address to contribute Ether to the contract, and it distinguishes between stakeholders and collaborators based on the contribution amount.
    * @dev The function checks if the contribution amount is greater than zero, and if the sender is a stakeholder, it updates the stakeholder's balance. If the sender is a collaborator, it updates the collaborator's balance.
    * @dev If the total contribution of the sender meets or exceeds the `STAKEHOLDER_MIN_CONTRIBUTION`, the sender is granted the `STAKEHOLDER_ROLE`.
    * @return The updated total balance of the contract.
    */
    function contribute() payable external returns (uint256) {
        require(msg.value > 0, "Invalid amount");

        if (!hasRole(STAKEHOLDER_ROLE, msg.sender)) {
            uint256 totalContributions = contributors[msg.sender] + msg.value;

            if (totalContributions >= STAKEHOLDER_MIN_CONTRIBUTION) {
                stakeholders[msg.sender] = msg.value;
                _setupRole(STAKEHOLDER_ROLE, msg.sender);
            } else {
                _setupRole(COLLABORATOR_ROLE, msg.sender);
            }

            contributors[msg.sender] += msg.value;
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


    /**
    * @notice Get the details of a specific proposal by its ID.
    * @dev Returns the information of a proposal with the specified `proposalID`, including its ID, requested amount, vote counts, duration, title, description, payment status, passed status, beneficiary address, proposer's address, and executor's address.
    * @param proposalID The unique identifier of the proposal to retrieve.
    * @return A `Proposals` struct containing the proposal details.
    */
    function getProposals(uint256 proposalID) external view returns(Proposals memory) {
        return raisedProposals[proposalID];
    }

    /**
    * @notice Get information about all proposals in the contract.
    * @dev Returns an array of `Proposals` structs, each containing the details of a proposal. The array includes information about all the proposals stored in the contract.
    * @return An array of `Proposals` structs representing all the proposals in the contract.
    */
    function getAllProposals() external view returns(Proposals[] memory props){
        props = new Proposals[](totalProposals);
        for (uint i = 0; i < totalProposals; i++) {
            props[i] = raisedProposals[i];
        }

    }

    /**
    * @notice Get the votes for a specific proposal.
    * @dev Returns an array of `Voted` structs, each representing a vote for the specified proposal. You can use this function to retrieve the votes for a specific proposal by providing its ID.
    * @param proposalID The ID of the proposal for which you want to retrieve the votes.
    * @return An array of `Voted` structs containing the votes for the specified proposal.
    */
    function getProposalVote(uint256 proposalID) external view returns(Voted[] memory){
        return votedOn[proposalID];
    }

    /**
    * @notice Get the list of proposals voted on by the caller, who is a stakeholder.
    * @dev Returns an array of proposal IDs representing the proposals voted on by the caller, who must have the stakeholder role.
    * @return An array of uint256 values representing the IDs of the proposals voted on by the caller.
    */
    function getStakeholdersVotes() stakeholderOnly("Unauthorized") external view returns(uint256[] memory){
        return stakeholderVotes[msg.sender];
    }

    /**
    * @notice Get the balance of the caller, who is a stakeholder.
    * @dev Returns the balance associated with the caller's address, who must have the stakeholder role.
    * @return The balance of the caller in wei.
    */
    function getStakeholdersBalances() stakeholderOnly("unauthorized") external view returns(uint256){
        return stakeholders[msg.sender];

    }

    /**
    * @notice Get the total balance held by the contract.
    * @dev Returns the total balance currently stored in the contract.
    * @return The total balance in wei.
    */
    function getTotalBalance() external view returns(uint256){
        return balance;

    }

    /**
    * @notice Check if the caller is a stakeholder.
    * @dev Returns `true` if the caller is a stakeholder, meaning they have made a contribution above the minimum threshold.
    * @return `true` if the caller is a stakeholder; otherwise, `false`.
    */
    function stakeholderStatus() external view returns(bool){
        return stakeholders[msg.sender] > 0;
    }

    /**
    * @notice Check if the caller is a contributor.
    * @dev Returns `true` if the caller is a contributor, indicating that they have made a contribution to the contract.
    * @return `true` if the caller is a contributor; otherwise, `false`.
    */
    function isContributor() external view returns(bool){
        return contributors[msg.sender] > 0;
    }

    /**
    * @notice Get the balance of the caller as a contributor.
    * @dev Returns the balance (amount contributed) of the caller as a contributor to the contract.
    * @return The balance (amount contributed) of the caller.
    */
    function getContributorsBalance() contributorOnly("unathorized") external view returns(uint256){
        return contributors[msg.sender];
    }

    /**
    * @notice Get the address of the contract's deployer.
    * @dev Returns the Ethereum address of the contract's deployer.
    * @return The Ethereum address of the contract's deployer.
    */
    function getDeployer()external view returns(address){
        return deployer;

    }





}