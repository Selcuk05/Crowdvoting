// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";

// 0xA05076575058D6625E13973DA6B5079e8f2Ce5dd
contract CrowdVoting is VRFConsumerBaseV2 {

    error CrowdVoting__VoteNotActive(uint256 voteId);
    error CrowdVoting__VoteIsActive(uint256 voteId);
    error CrowdVoting__CouldNotAllocate(uint256 voteId, address allocatee);
    error CrowdVoting__AlreadyVoted(uint256 voteId, address voter);

    event VoteCreated(uint256 requestId, uint256 voteId);
    event VoteSubmitted(uint256 voteId, address voter);
    event FundsAllocated(address allocatee, uint256 allocatedFunds);

    struct Vote {
        string subject;
        uint64 yes;
        uint64 no;
        uint40 period;
        uint40 startDate;
        uint256 allocatedFunds; // in theory, funds allocated by a municipality
        address allocatee; // in theory, the org. that will receive the funds if the vote passes
    }

    uint64 s_subscriptionId;
    address s_owner;
    VRFCoordinatorV2Interface COORDINATOR;
    address vrfCoordinator = 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625;
    bytes32 s_keyHash = 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c;
    uint32 callbackGasLimit = 40000;
    uint16 requestConfirmations = 3;
    uint32 numWords = 1;

    mapping(uint256 voteId => Vote vote) public votes;
    mapping(uint256 voteId => mapping(address voter => bool voted)) hasVoted;
    mapping(uint256 requestId => uint256 voteId) public voteIdRegister;

    constructor(uint64 subscriptionId) VRFConsumerBaseV2(vrfCoordinator) {
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        s_owner = msg.sender;
        s_subscriptionId = subscriptionId;
    }

    modifier onlyOwner() {
        require(msg.sender == s_owner);
        _;
    }

    // example subject: "Should Company A get 0.5 ETH to serve coffee in the main square?"
    function createVote(string memory subject, uint40 period, address allocatee) external payable onlyOwner returns (uint256 voteIdRequest) {
        voteIdRequest = COORDINATOR.requestRandomWords(
            s_keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
       );

       Vote memory vote;
       vote.subject = subject;
       vote.period = period;
       vote.startDate = uint40(block.timestamp);
       vote.allocatedFunds = msg.value;
       vote.allocatee = allocatee;

       uint256 curVoteId = voteIdRegister[voteIdRequest];
       votes[curVoteId] = vote;

       emit VoteCreated(voteIdRequest, curVoteId);
    }

    function submitVote(uint256 voteId, bool opinion) external {
        if(!voteIsActive(voteId)) revert CrowdVoting__VoteNotActive(voteId);
        if(hasVoted[voteId][msg.sender]) revert CrowdVoting__AlreadyVoted(voteId, msg.sender);

        Vote memory vote = votes[voteId];
        opinion ? vote.yes += 1 : vote.no += 1;

        votes[voteId] = vote;
        hasVoted[voteId][msg.sender] = true;

        emit VoteSubmitted(voteId, msg.sender);
    }

    function completeVote(uint256 voteId) external onlyOwner {
        if(voteIsActive(voteId)) revert CrowdVoting__VoteIsActive(voteId);

        Vote memory vote = votes[voteId];
        if(vote.yes > vote.no){
            (bool sent, ) = payable(vote.allocatee).call{value: vote.allocatedFunds}("");
            if(!sent) revert CrowdVoting__CouldNotAllocate(voteId, vote.allocatee);
        }else{
            (bool sent, ) = payable(s_owner).call{value: vote.allocatedFunds}("");
            if(!sent) revert CrowdVoting__CouldNotAllocate(voteId, s_owner);
        }

        emit FundsAllocated(vote.allocatee, vote.allocatedFunds);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        voteIdRegister[requestId] = randomWords[0]; 
    }

    function voteIsActive(uint256 voteId) internal view returns(bool active){
        Vote memory curVote = votes[voteId];
        active = curVote.startDate + curVote.period > block.timestamp;
    }



}
