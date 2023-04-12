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
        address nominatedHunter;
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
    mapping(address => uint256) private balanceByAddress;
    uint256[] private bountyIds;
    uint256 public minBountyRealizationTime = 3 days;

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
        require(_deadline > block.timestamp + minBountyRealizationTime, "Deadline must be > 3 days");
        require(_hunterReward > 0, "Hunter reward must be > 0");
        require(_validatorReward > 0, "Validator reward must be > 0");

        Bounty memory bounty = Bounty(
            bountyId,
            BountyStatus.OPEN,
            msg.sender,
            ZERO_ADDRESS,
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

        uint256 totalAmount = bounty.validatorReward + bounty.hunterReward;
        bool success = token.transfer(address(this), totalAmount);
        require(success, "Error transfering funds");
        balanceByAddress[msg.sender] += totalAmount;
        bountyById[bountyId] = bounty;
        bountyIds.push(bountyId);
        bountyId++;
    }

    function applyForBounty(uint256 _bountyId) external {
        User memory user = userByAddress[msg.sender];
        Bounty storage bounty = bountyById[_bountyId];
        require(bounty.status == BountyStatus.OPEN, "Bounty not open");
        require(user.reputation >= bounty.minHunterReputation, "Reputation too low");

        for(uint256 i; i < bounty.hunterCandidates.length; i++){
            require(bounty.hunterCandidates[i] != msg.sender, "Already applied");
        }

        uint256 totalAmount = bounty.validatorReward + bounty.minHunterDeposit;

        bounty.hunterCandidates.push(msg.sender);
    }

    function nominateCandidate(uint256 _bountyId, address _nominatedAddress) external {
        Bounty storage bounty = bountyById[_bountyId];
        require(bounty.status == BountyStatus.OPEN, "Bounty not open");
        require(bounty.creator == msg.sender, "Not bounty creator");
        bool isCandidate;
        for(uint256 i; i < bounty.hunterCandidates.length; i++){
            if(bounty.hunterCandidates[i] == _nominatedAddress){
                isCandidate = true;
                break;
            }
        }

        require(isCandidate, "Not a bounty candidate");

        bounty.nominatedHunter = _nominatedAddress;
    }

    function acceptNomination(uint256 _bountyId) external {
        Bounty storage bounty = bountyById[_bountyId];
        require(bounty.nominatedHunter == msg.sender, "Must be nominated");
        uint256 totalAmount = bounty.validatorReward + bounty.minHunterDeposit;
        bool success = token.transfer(address(this), totalAmount);
        require(success, "Error transfering funds");
        balanceByAddress[msg.sender] += totalAmount;
        bounty.hunter = msg.sender;
        bounty.status = BountyStatus.IN_PROGRESS;
    }
}