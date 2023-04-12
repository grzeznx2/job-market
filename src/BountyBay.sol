pragma solidity ^0.8.0;

contract BountyBay {
    enum BountStatus {
        TO_DO,
        IN_PROGRESS,
        REVIEW,
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

    struct User {
        address userAddress;
        bool isValidator;
        uint256 reputation;
        uint256[] bountiesCompleted;
        uint256[] bountiesCreated;
        uint256[] bountiesFailed;
    }

    mapping(uint256 => Bounty) private bountyById;
    mapping(uint256 => address) private creatorByBountyId;
    uint256[] private bountyIds;
}