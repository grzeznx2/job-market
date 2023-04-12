pragma solidity ^0.8.0;

contract BountyBay {
    address constant ZERO_ADDRESS = address(0);

    enum BountyStatus {
        TO_DO,
        IN_PROGRESS,
        REVIEW,
        DONE,
        CANCELLED
    }

    struct Bounty {
        uint256 id;
        address creator;
        address hunter;
        address validator;
        string name;
        string description;
        string acceptanceCriteria;
        uint256 deadline;
        uint256 hunterReward;
        uint256 validatorReward;
        uint256 minHunterReputation;
        uint256 minHunterDeposit;
    }

    struct User {
        address userAddress;
        bool isValidator;
        uint256 reputation;
        uint256[] bountiesCompleted;
        uint256[] bountiesCreated;
        uint256[] bountiesFailed;
        uint256[] bountiesValidated;
        uint256[] bountiesAssignedToDo;
        uint256[] bountiesAssignedToValidation;
    }

    uint256 private bountyId;
    mapping(uint256 => Bounty) private bountyById;
    mapping(uint256 => address) private creatorByBountyId;
    mapping(uint256 => address) private hunterByBountyId;
    mapping(uint256 => address) private validatorByBountyId;
    uint256[] private bountyIds;

    function createBounty(
        string memory _name,
        string memory _description,
        string memory _acceptanceCriteria,
        uint256 _deadline,
        uint256 _hunterReward,
        uint256 _validatorReward,
        uint256 _minHunterReputation,
        uint256 _minHunterDeposit
    ) external {
        require(_deadline > block.timestamp, "Invalid deadline");
        require(_hunterReward > 0, "Hunter reward must be > 0");
        require(_validatorReward > 0, "Validator reward must be > 0");

        bountyById[bountyId] = Bounty(
            bountyId,
            msg.sender,
            ZERO_ADDRESS,
            ZERO_ADDRESS,
            _name,
            _description,
            _acceptanceCriteria,
            _deadline,
            _hunterReward,
            _validatorReward,
            _minHunterReputation,
            _minHunterDeposit
        );
        bountyIds.push(bountyId);
        bountyId++;
    }
}