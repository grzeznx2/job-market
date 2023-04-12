pragma solidity ^0.8.0;

contract BountyBay {
    enum BountyStatus {
        TO_DO,
        IN_PROGRESS,
        DONE,
        CANCELLED
    }

    struct Bounty {
        uint256 id;
        address creator;
        string name;
        string description;
        string acceptanceCriteria;
        uint256 deadline;
        uint256 hunterReward;
        uint256 validatorReward;
        uint256 minHunterReputation;
        uint256 minHunterDeposit;
        uint256 minHunterForValdiatorDeposit;
    }
}