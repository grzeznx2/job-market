pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract BountyBay {
    address constant ZERO_ADDRESS = address(0);

    enum BountyStatus {
        INVALID,
        OPEN, 
        IN_PROGRESS, 
        REVIEW, 
        ACCEPTED,
        NOT_ACCEPTED,
        VALIDATING,
        ENDED
    }

    struct Bounty {
        uint256 id;
        BountyStatus status;
        address creator;
        address hunter;
        address nominatedHunter;
        address validator;
        address token;
        string name;
        string description;
        string acceptanceCriteria;
        uint256 deadline;
        uint256 hunterReward;
        uint256 validatorReward;
        uint256 minHunterReputation;
        uint256 minHunterDeposit;
        address[] hunterCandidates;
        uint256 nominationAcceptanceDeadline;
        string realisationProof;
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

    struct Application {
        address user;
        uint256 bountyId;
        uint256 validUntil;
    }

    mapping(address => mapping(uint256 => Application)) private applicationByBountyIdAndAddress;
    address public admin;
    uint256 private bountyId;
    mapping(uint256 => Bounty) private bountyById;
    mapping(uint256 => address) private creatorByBountyId;
    mapping(uint256 => address) private hunterByBountyId;
    mapping(uint256 => address) private validatorByBountyId;
    mapping(address => User) private userByAddress;
    uint256[] private bountyIds;
    uint256 public minBountyRealizationTime = 3 days;
    uint256 public minNominationAcceptanceTime = 1 days;
    mapping(address => bool) public isWhitelistedToken;
    mapping(address => mapping(address => uint256)) private tokenBalanceByUser;
    mapping(address => mapping(address => uint256)) private claimableTokenBalanceByUser;

      constructor() {
        admin = msg.sender;
    }

     modifier onlyAdmin() {
        require(msg.sender == admin, "Only for admin");
        _;
    }

    function createBounty(
        address _token,
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
        require(isWhitelistedToken[_token], "Invalid token");

        Bounty memory bounty = Bounty(
            bountyId,
            BountyStatus.OPEN,
            msg.sender,
            ZERO_ADDRESS,
            ZERO_ADDRESS,
            ZERO_ADDRESS,
            _token,
            _name,
            _description,
            _acceptanceCriteria,
            _deadline,
            _hunterReward,
            _validatorReward,
            _minHunterReputation,
            _minHunterDeposit,
            new address[](0),
            0,
            ''
        );

        uint256 totalAmount = bounty.validatorReward + bounty.hunterReward;
        /*
        If user has funds in the contract, take it from here, otherwise create transfer
         */
        if(claimableTokenBalanceByUser[msg.sender][_token] >= totalAmount){
            claimableTokenBalanceByUser[msg.sender][_token] -= totalAmount;
        }else{
            bool success = IERC20(_token).transferFrom(msg.sender, address(this), totalAmount);
            require(success, "Error transfering funds");

        }
        tokenBalanceByUser[msg.sender][_token] += totalAmount;
        bountyById[bountyId] = bounty;
        bountyIds.push(bountyId);
        bountyId++;
    }

    function applyForBounty(uint256 _bountyId, uint256 _estimatedRealizationTime) external {
        User memory user = userByAddress[msg.sender];
        Bounty storage bounty = bountyById[_bountyId];
        require(bounty.status == BountyStatus.OPEN, "Bounty not open");
        require(user.reputation >= bounty.minHunterReputation, "Reputation too low");

        uint256 applicationValidUntil = bounty.deadline - minNominationAcceptanceTime - _estimatedRealizationTime;

        require(applicationValidUntil >= block.timestamp, "Too late");

        for(uint256 i; i < bounty.hunterCandidates.length; i++){
            require(bounty.hunterCandidates[i] != msg.sender, "Already applied");
        }

        // uint256 totalAmount = bounty.validatorReward + bounty.minHunterDeposit;

        applicationByBountyIdAndAddress[msg.sender][_bountyId] = Application(
            msg.sender,
            _bountyId,
            applicationValidUntil
        );

        bounty.hunterCandidates.push(msg.sender);
    }

    function nominateCandidate(uint256 _bountyId, address _nominatedAddress) external {
        Bounty storage bounty = bountyById[_bountyId];
        require(bounty.status == BountyStatus.OPEN, "Bounty not open");
        require(bounty.creator == msg.sender, "Not bounty creator");
        require(msg.sender != _nominatedAddress, "Cannot nominate yourself");
        bool isCandidate;
        for(uint256 i; i < bounty.hunterCandidates.length; i++){
            if(bounty.hunterCandidates[i] == _nominatedAddress){
                isCandidate = true;
                break;
            }
        }

        require(isCandidate, "Not a bounty candidate");

        Application memory application = applicationByBountyIdAndAddress[_nominatedAddress][_bountyId];

        require(application.validUntil >= block.timestamp, "Too late");

        bounty.nominationAcceptanceDeadline = block.timestamp + minNominationAcceptanceTime;
        bounty.nominatedHunter = _nominatedAddress;
    }

    function acceptNomination(uint256 _bountyId) external {
        Bounty storage bounty = bountyById[_bountyId];
        require(bounty.nominatedHunter == msg.sender, "Must be nominated");
        require(bounty.nominationAcceptanceDeadline >= block.timestamp, "Acceptance deadline passed");
        address token = bounty.token;
        uint256 totalAmount = bounty.validatorReward + bounty.minHunterDeposit;
        if(claimableTokenBalanceByUser[msg.sender][token] >= totalAmount){
            claimableTokenBalanceByUser[msg.sender][token] -= totalAmount;
        }else{
            bool success = IERC20(token).transferFrom(msg.sender, address(this), totalAmount);
            require(success, "Error transfering funds");
        }
        tokenBalanceByUser[msg.sender][token] += totalAmount;
        bounty.hunter = msg.sender;
        bounty.status = BountyStatus.IN_PROGRESS;
    }

    function cancelCandidateNomination(uint256 _bountyId) external {
        Bounty storage bounty = bountyById[_bountyId];
        require(bounty.status == BountyStatus.OPEN, "Bounty not open");
        require(bounty.creator == msg.sender, "Not bounty creator");
        require(bounty.nominatedHunter != ZERO_ADDRESS, "Missing nominated hunter");
        bounty.nominatedHunter = ZERO_ADDRESS;
        bounty.nominationAcceptanceDeadline = 0;
    }

    function addBountyToReview(uint256 _bountyId, string calldata _realisationProof) external {
        Bounty storage bounty = bountyById[_bountyId];
        require(bounty.status == BountyStatus.IN_PROGRESS, "Bounty not in progress");
        require(bounty.hunter == msg.sender, "Not bounty hunter");
        require(bounty.deadline >= block.timestamp, "Deadline passed");
        bounty.realisationProof = _realisationProof;
        bounty.status = BountyStatus.REVIEW;
    }

    function whitelistToken(address _token) external onlyAdmin {
        isWhitelistedToken[_token] = true;
    }

    function blacklistToken(address _token) external onlyAdmin {
        isWhitelistedToken[_token] = false;
    }

    function addFunds(uint256 _amount, address _token) external {
        require(isWhitelistedToken[_token], "Token not allowed");
        claimableTokenBalanceByUser[msg.sender][_token] += _amount;
        bool success = IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        require(success, "Error transferring funds");
    }

    function withdrawFunds(uint256 _amount, address _token) external {
        require(claimableTokenBalanceByUser[msg.sender][_token] >= _amount, "Amount exceeds balance");
        claimableTokenBalanceByUser[msg.sender][_token] -= _amount;
        bool success = IERC20(_token).transfer(msg.sender, _amount);
        require(success, "Error transferring funds");
    }

    function acceptBountyCompletion(uint256 _bountyId) external {
        Bounty storage bounty = bountyById[_bountyId];

        require(bounty.creator == msg.sender, "Not bounty creator");
        require(bounty.status == BountyStatus.REVIEW, "Bounty not under review");

        address hunter = bounty.hunter;
        address token = bounty.token;
        uint256 validatorReward = bounty.validatorReward;
        uint256 hunterReward = bounty.hunterReward;
        uint256 hunterDeposits = bounty.minHunterDeposit + validatorReward;
        uint256 hunterAmount = hunterReward + hunterDeposits;

        claimableTokenBalanceByUser[hunter][token] += hunterAmount;
        tokenBalanceByUser[hunter][token] -= hunterDeposits;
        claimableTokenBalanceByUser[msg.sender][token] += validatorReward;
        tokenBalanceByUser[msg.sender][token] -= (validatorReward + hunterAmount);

        bounty.status = BountyStatus.ACCEPTED;

    }

    function rejectBountyCompletion(uint256 _bountyId) external {
        Bounty storage bounty = bountyById[_bountyId];

        require(bounty.creator == msg.sender, "Not bounty creator");
        require(bounty.status == BountyStatus.REVIEW, "Bounty not under review");

        bounty.status = BountyStatus.NOT_ACCEPTED;
    }

    function acceptBountyRejection(uint256 _bountyId) external {
        Bounty storage bounty = bountyById[_bountyId];

        require(bounty.hunter == msg.sender, "Not bounty hunter");
        require(bounty.status == BountyStatus.NOT_ACCEPTED, "Bounty not rejected");

        address creator = bounty.creator;
        address token = bounty.token;
        uint256 validatorReward = bounty.validatorReward;
        uint256 hunterReward = bounty.hunterReward;
        uint256 minHunterDeposit = bounty.minHunterDeposit;
        uint256 creatorAmount = validatorReward + hunterReward + minHunterDeposit;

        claimableTokenBalanceByUser[creator][token] += creatorAmount;
        tokenBalanceByUser[creator][token] -= (validatorReward + hunterReward);
        claimableTokenBalanceByUser[msg.sender][token] += validatorReward;
        tokenBalanceByUser[msg.sender][token] -= (validatorReward + minHunterDeposit);

        bounty.status = BountyStatus.ENDED;
    }

    function passBountyToValidation(uint256 _bountyId) external {
        Bounty storage bounty = bountyById[_bountyId];

        require(bounty.hunter == msg.sender, "Not bounty hunter");
        require(bounty.status == BountyStatus.NOT_ACCEPTED, "Bounty not rejected");

        bounty.status = BountyStatus.VALIDATING;
    }


}