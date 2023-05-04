pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BountyBay {
    address constant ZERO_ADDRESS = address(0);

    enum BountyStatus {
        UNITIALIZED,
        OPEN,
        HUNTER_NOMINATED,
        IN_PROGRESS,
        REVIEW,
        ACCEPTED,
        NOT_ACCEPTED,
        VALIDATING,
        ENDED
    }

    enum ApplicationStatus {
        UNINITIALIZED,
        PENDING,
        NOMINATED,
        ACCEPTED,
        CANCELED,
        CANCELED_AFTER_NOMINATION_BY_HUNTER,
        CANCELED_AFTER_NOMINATION_BY_CREATOR,
        CANCELED_AFTER_ACCEPTANCE_BY_HUNTER,
        CANCELED_AFTER_ACCEPTANCE_BY_CREATOR
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
        uint256 nominationAcceptanceTime;
        uint256 reviewPeriodTime;
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
        uint256 canceledAfterNomination;
        uint256 canceledAfterAcceptance;
    }

    struct Application {
        address hunter;
        uint256 bountyId;
        uint256 proposedDeadline;
        uint256 proposedReward;
        uint256 validUntil;
        uint256 acceptedAt;
        ApplicationStatus status;
    }

    mapping(address => mapping(uint256 => Application))
        private applicationByBountyIdAndAddress;
    address public admin;
    uint256 private bountyId;
    mapping(uint256 => Bounty) private bountyById;
    mapping(uint256 => address) private creatorByBountyId;
    mapping(uint256 => address) private hunterByBountyId;
    mapping(uint256 => address) private validatorByBountyId;
    mapping(address => User) private userByAddress;
    uint256[] private bountyIds;
    mapping(address => uint256[]) private bountyIdsByCreator;
    // uint256 public minBountyRealizationTime = 3 days;
    // uint256 public minNominationAcceptanceTime = 1 days;
    // uint256 public minReviewPeriodTime = 1 days;
    mapping(address => bool) public isWhitelistedToken;
    mapping(address => mapping(address => uint256)) private tokenBalanceByUser;
    mapping(address => mapping(address => uint256))
        private claimableTokenBalanceByUser;

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
        uint256 _nominationAcceptanceTime,
        uint256 _reviewPeriodTime,
        uint256 _hunterReward,
        uint256 _validatorReward,
        uint256 _minHunterReputation,
        uint256 _minHunterDeposit
    ) external {
        require(_deadline > block.timestamp, "Deadline must be in the future");
        require(
            _nominationAcceptanceTime > 0,
            "Nomination acceptance time must be > 0"
        );
        require(_reviewPeriodTime > 0, "Review Period Time must be >= 0");
        require(_hunterReward >= 0, "Hunter reward must be > 0");
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
            _nominationAcceptanceTime,
            _reviewPeriodTime,
            _hunterReward,
            _validatorReward,
            _minHunterReputation,
            _minHunterDeposit,
            new address[](0),
            0,
            ""
        );

        uint256 totalAmount = bounty.validatorReward + bounty.hunterReward;
        /*
        If user has funds in the contract, take it from here, otherwise create transfer
         */
        if (claimableTokenBalanceByUser[msg.sender][_token] >= totalAmount) {
            claimableTokenBalanceByUser[msg.sender][_token] -= totalAmount;
        } else {
            bool success = IERC20(_token).transferFrom(
                msg.sender,
                address(this),
                totalAmount
            );
            require(success, "Error transfering funds");
        }
        tokenBalanceByUser[msg.sender][_token] += totalAmount;
        bountyById[bountyId] = bounty;
        bountyIdsByCreator[msg.sender].push(bountyId);
        bountyIds.push(bountyId);
        bountyId++;
    }

    function applyForBounty(
        uint256 _bountyId,
        uint256 _proposedDeadline,
        uint256 _proposedReward,
        uint256 _validUntil
    ) external {
        User memory user = userByAddress[msg.sender];
        Bounty storage bounty = bountyById[_bountyId];
        require(bounty.creator != msg.sender, "Cannot apply for own bounty");
        require(bounty.status == BountyStatus.OPEN, "Bounty not open");
        require(
            user.reputation >= bounty.minHunterReputation,
            "Reputation too low"
        );
        require(
            _proposedDeadline > block.timestamp,
            "Deadline must be in the future"
        );
        require(_proposedReward > 0, "Proposed reward must be > 0");
        require(_validUntil >= block.timestamp, "Too late");

        require(
            applicationByBountyIdAndAddress[msg.sender][_bountyId].hunter ==
                address(0),
            "Already applied"
        );

        applicationByBountyIdAndAddress[msg.sender][_bountyId] = Application(
            msg.sender,
            _bountyId,
            _proposedDeadline,
            _proposedReward,
            _validUntil,
            0,
            ApplicationStatus.PENDING
        );

        bounty.hunterCandidates.push(msg.sender);
    }

    function nominateCandidate(
        uint256 _bountyId,
        address _nominatedAddress
    ) external {
        Bounty storage bounty = bountyById[_bountyId];
        require(bounty.status == BountyStatus.OPEN, "Bounty not open");
        require(bounty.creator == msg.sender, "Not bounty creator");
        require(msg.sender != _nominatedAddress, "Cannot nominate yourself");
        Application storage application = applicationByBountyIdAndAddress[
            _nominatedAddress
        ][_bountyId];
        require(application.hunter != address(0), "Not hunter candidate");
        require(
            application.validUntil >= block.timestamp,
            "Application no longer valid"
        );
        // TODO : Adjust creator balances regarding application proposed reward
        application.status = ApplicationStatus.NOMINATED;
        bounty.nominationAcceptanceDeadline =
            block.timestamp +
            bounty.nominationAcceptanceTime;
        bounty.nominatedHunter = _nominatedAddress;
        bounty.status = BountyStatus.HUNTER_NOMINATED;
    }

    function acceptNomination(uint256 _bountyId) external {
        Bounty storage bounty = bountyById[_bountyId];
        require(
            bounty.status == BountyStatus.HUNTER_NOMINATED,
            "Incorrect bounty status"
        );
        require(bounty.nominatedHunter == msg.sender, "Must be nominated");
        require(
            bounty.nominationAcceptanceDeadline >= block.timestamp,
            "Acceptance deadline passed"
        );
        Application storage application = applicationByBountyIdAndAddress[
            msg.sender
        ][_bountyId];
        address token = bounty.token;
        uint256 totalAmount = bounty.validatorReward + bounty.minHunterDeposit;
        if (claimableTokenBalanceByUser[msg.sender][token] >= totalAmount) {
            claimableTokenBalanceByUser[msg.sender][token] -= totalAmount;
        } else {
            bool success = IERC20(token).transferFrom(
                msg.sender,
                address(this),
                totalAmount
            );
            require(success, "Error transfering funds");
        }
        tokenBalanceByUser[msg.sender][token] += totalAmount;
        application.status = ApplicationStatus.ACCEPTED;
        bounty.hunterReward = application.proposedReward;
        bounty.deadline = application.proposedDeadline;
        bounty.hunter = msg.sender;
        bounty.status = BountyStatus.IN_PROGRESS;
    }

    function cancelApplication(uint256 _bountyId) external {
        Application storage application = applicationByBountyIdAndAddress[
            msg.sender
        ][_bountyId];
        ApplicationStatus status = application.status;

        if (status == ApplicationStatus.PENDING) {
            application.status = ApplicationStatus.CANCELED;
        } else if (status == ApplicationStatus.NOMINATED) {
            application.status = ApplicationStatus
                .CANCELED_AFTER_NOMINATION_BY_HUNTER;
            Bounty storage bounty = bountyById[_bountyId];
            bounty.nominatedHunter = ZERO_ADDRESS;
            bounty.nominationAcceptanceDeadline = 0;
            bounty.status = BountyStatus.OPEN;
            userByAddress[msg.sender].canceledAfterNomination += 1;
        } else if (status == ApplicationStatus.ACCEPTED) {
            application.status ==
                ApplicationStatus.CANCELED_AFTER_ACCEPTANCE_BY_HUNTER;
            Bounty storage bounty = bountyById[_bountyId];
            bounty.hunter = ZERO_ADDRESS;
            bounty.nominatedHunter = ZERO_ADDRESS;
            bounty.nominationAcceptanceDeadline = 0;
            bounty.status = BountyStatus.OPEN;
            userByAddress[msg.sender].canceledAfterAcceptance += 1;

            address creator = bounty.creator;
            address token = bounty.token;
            uint256 validatorReward = bounty.validatorReward;
            uint256 hunterReward = bounty.hunterReward;
            uint256 minHunterDeposit = bounty.minHunterDeposit;
            uint256 creatorAmount = validatorReward +
                hunterReward +
                minHunterDeposit;

            claimableTokenBalanceByUser[creator][token] += creatorAmount;
            tokenBalanceByUser[creator][token] -= (validatorReward +
                hunterReward);
            claimableTokenBalanceByUser[msg.sender][token] += validatorReward;
            tokenBalanceByUser[msg.sender][token] -= (validatorReward +
                minHunterDeposit);
        } else {
            revert("Invalid application status");
        }
    }

    function cancelCandidateNomination(uint256 _bountyId) external {
        Bounty storage bounty = bountyById[_bountyId];
        require(
            bounty.status == BountyStatus.HUNTER_NOMINATED,
            "Bounty not open"
        );
        require(bounty.creator == msg.sender, "Not bounty creator");
        Application storage application = applicationByBountyIdAndAddress[
            bounty.nominatedHunter
        ][_bountyId];
        application.status = ApplicationStatus
            .CANCELED_AFTER_NOMINATION_BY_CREATOR;
        bounty.nominatedHunter = ZERO_ADDRESS;
        bounty.nominationAcceptanceDeadline = 0;
        bounty.status = BountyStatus.OPEN;
    }

    function addBountyToReview(
        uint256 _bountyId,
        string calldata _realisationProof
    ) external {
        Bounty storage bounty = bountyById[_bountyId];
        require(
            bounty.status == BountyStatus.IN_PROGRESS,
            "Bounty not in progress"
        );
        require(bounty.hunter == msg.sender, "Not bounty hunter");
        require(bounty.deadline >= block.timestamp, "Deadline passed");
        bounty.realisationProof = _realisationProof;
        bounty.status = BountyStatus.REVIEW;
    }

    function getBountyApplications(
        uint256 _bountyId
    ) external view returns (Application[] memory) {
        address[] memory hunterCandidates = bountyById[_bountyId]
            .hunterCandidates;
        uint256 applicationsCount = hunterCandidates.length;
        Application[] memory applications = new Application[](
            applicationsCount
        );
        for (uint256 i; i < applicationsCount; i++) {
            applications[i] = applicationByBountyIdAndAddress[
                hunterCandidates[i]
            ][_bountyId];
        }
        return applications;
    }

    function getBountiesByCreator(
        address _creator
    ) external view returns (Bounty[] memory) {
        uint256[] memory creatorBountyIds = bountyIdsByCreator[_creator];
        uint256 bountyIdsCount = creatorBountyIds.length;
        Bounty[] memory bounties = new Bounty[](bountyIdsCount);
        for (uint256 i; i < bountyIdsCount; i++) {
            bounties[i] = bountyById[creatorBountyIds[i]];
        }
        return bounties;
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
        bool success = IERC20(_token).transferFrom(
            msg.sender,
            address(this),
            _amount
        );
        require(success, "Error transferring funds");
    }

    function withdrawFunds(uint256 _amount, address _token) external {
        require(
            claimableTokenBalanceByUser[msg.sender][_token] >= _amount,
            "Amount exceeds balance"
        );
        claimableTokenBalanceByUser[msg.sender][_token] -= _amount;
        bool success = IERC20(_token).transfer(msg.sender, _amount);
        require(success, "Error transferring funds");
    }

    function acceptBountyCompletion(uint256 _bountyId) external {
        Bounty storage bounty = bountyById[_bountyId];

        require(bounty.creator == msg.sender, "Not bounty creator");
        require(
            bounty.status == BountyStatus.REVIEW,
            "Bounty not under review"
        );

        address hunter = bounty.hunter;
        address token = bounty.token;
        uint256 validatorReward = bounty.validatorReward;
        uint256 hunterReward = bounty.hunterReward;
        uint256 hunterDeposits = bounty.minHunterDeposit + validatorReward;
        uint256 hunterAmount = hunterReward + hunterDeposits;

        // TODO: Failed => Find why?
        claimableTokenBalanceByUser[hunter][token] += hunterAmount;
        tokenBalanceByUser[hunter][token] -= hunterDeposits;
        claimableTokenBalanceByUser[msg.sender][token] += validatorReward;
        tokenBalanceByUser[msg.sender][token] -= (validatorReward +
            hunterAmount);

        bounty.status = BountyStatus.ACCEPTED;
    }

    function rejectBountyCompletion(uint256 _bountyId) external {
        Bounty storage bounty = bountyById[_bountyId];

        require(bounty.creator == msg.sender, "Not bounty creator");
        require(
            bounty.status == BountyStatus.REVIEW,
            "Bounty not under review"
        );

        bounty.status = BountyStatus.NOT_ACCEPTED;
    }

    function acceptBountyRejection(uint256 _bountyId) external {
        Bounty storage bounty = bountyById[_bountyId];

        require(bounty.hunter == msg.sender, "Not bounty hunter");
        require(
            bounty.status == BountyStatus.NOT_ACCEPTED,
            "Bounty not rejected"
        );

        address creator = bounty.creator;
        address token = bounty.token;
        uint256 validatorReward = bounty.validatorReward;
        uint256 hunterReward = bounty.hunterReward;
        uint256 minHunterDeposit = bounty.minHunterDeposit;
        uint256 creatorAmount = validatorReward +
            hunterReward +
            minHunterDeposit;

        claimableTokenBalanceByUser[creator][token] += creatorAmount;
        tokenBalanceByUser[creator][token] -= (validatorReward + hunterReward);
        claimableTokenBalanceByUser[msg.sender][token] += validatorReward;
        tokenBalanceByUser[msg.sender][token] -= (validatorReward +
            minHunterDeposit);

        bounty.status = BountyStatus.ENDED;
    }

    function passBountyToValidation(uint256 _bountyId) external {
        Bounty storage bounty = bountyById[_bountyId];

        require(bounty.hunter == msg.sender, "Not bounty hunter");
        require(
            bounty.status == BountyStatus.NOT_ACCEPTED,
            "Bounty not rejected"
        );

        bounty.status = BountyStatus.VALIDATING;
    }

    function updateApplication(
        uint256 _bountyId,
        uint256 _proposedDeadline,
        uint256 _proposedReward,
        uint256 _validUntil
    ) external {
        require(
            _proposedReward != 0 || _proposedDeadline != 0 || _validUntil != 0,
            "Must edit at least one field"
        );
        // TODO: also check for bounty status?

        Application storage application = applicationByBountyIdAndAddress[
            msg.sender
        ][_bountyId];
        require(
            application.status == ApplicationStatus.PENDING,
            "Invalid status"
        );
        if (_proposedDeadline != 0) {
            require(
                _proposedDeadline > block.timestamp,
                "Deadline must be in the future"
            );

            application.proposedDeadline = _proposedDeadline;
        }
        if (_proposedReward != 0) {
            application.proposedReward = _proposedReward;
        }
        if (_validUntil != 0) {
            require(_validUntil >= block.timestamp, "Too late");
            application.validUntil = _validUntil;
        }
    }
}
