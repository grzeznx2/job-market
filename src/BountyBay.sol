pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract BountyBay {
    address constant ZERO_ADDRESS = address(0);

    enum BountyStatus {
        INVALID,
        OPEN,
        IN_PROGRESS,
        REVIEW,
        DONE,
        CANCELLED
    }

    struct Bounty {
        uint256 id;
        BountyStatus status;
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
        address[] hunterCandidates;
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
    mapping(address => User) private userByAddress;
    uint256[] private bountyIds;

    IERC20 public token;

    constructor(IERC20 _token){
        token = _token;
    }

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
            BountyStatus.OPEN,
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
            _minHunterDeposit,
            new address[](0)
        );
        bountyIds.push(bountyId);
        bountyId++;
    }

    function applyForBounty(uint256 _bountyId) external {
        User memory user = userByAddress[msg.sender];
        Bounty storage bounty = bountyById[_bountyId];
        require(bounty.creator != msg.sender, "Cannot apply for your own bounty");
        require(bounty.status == BountyStatus.OPEN, "Bounty not open");
        require(user.reputation >= bounty.minHunterReputation, "Reputation too low");

        for(uint256 i; i < bounty.hunterCandidates.length; i++){
            require(bounty.hunterCandidates[i] != msg.sender, "Already applied");
        }

        uint256 totalAmount = bounty.validatorReward + bounty.minHunterDeposit;

        require(token.balanceOf(msg.sender) >= totalAmount, "Insufficient funds");

        token.approve(address(this), totalAmount);
        bounty.hunterCandidates.push(msg.sender);
    }
}