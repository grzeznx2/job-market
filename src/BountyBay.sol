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
        OPEN_TO_NOMINATION,
        NOMINATED,
        ACCEPTED,
        CANCELED_BEFORE_NOMINATION,
        CANCELED_AFTER_NOMINATION_BY_HUNTER,
        CANCELED_AFTER_NOMINATION_BY_CREATOR
    }

    enum CanceledBy {
        NONE,
        HUNTER,
        CREATOR
    }

    function getApplicationStatus(
        Application memory _application
    ) internal pure returns (ApplicationStatus) {
        if (_application.canceledAt != 0) {
            if (_application.nominatedAt != 0) {
                if (_application.canceledBy == CanceledBy.HUNTER) {
                    return
                        ApplicationStatus.CANCELED_AFTER_NOMINATION_BY_HUNTER;
                } else {
                    return
                        ApplicationStatus.CANCELED_AFTER_NOMINATION_BY_CREATOR;
                }
            } else {
                return ApplicationStatus.CANCELED_BEFORE_NOMINATION;
            }
        } else if (_application.nominationAcceptedAt != 0) {
            return ApplicationStatus.ACCEPTED;
        } else if (_application.nominatedAt != 0) {
            return ApplicationStatus.NOMINATED;
        } else {
            return ApplicationStatus.OPEN_TO_NOMINATION;
        }
    }

    function getBountyApplicationStatus(
        Application memory _application
    ) internal pure returns (ApplicationStatus) {
        if (_application.canceledAt != 0) {
            if (_application.canceledBy == CanceledBy.HUNTER) {
                if (_application.nominatedAt != 0) {
                    if (_application.nominationAcceptedAt == 0) {
                        return
                            ApplicationStatus
                                .CANCELED_AFTER_NOMINATION_BY_HUNTER;
                    } else {
                        return
                            ApplicationStatus
                                .CANCELED_AFTER_ACCEPTANCE_BY_HUNTER;
                    }
                } else {
                    return ApplicationStatus.CANCELED;
                }
            } else {
                if (_application.nominationAcceptedAt == 0) {
                    return
                        ApplicationStatus.CANCELED_AFTER_NOMINATION_BY_CREATOR;
                } else {
                    return
                        ApplicationStatus.CANCELED_AFTER_ACCEPTANCE_BY_CREATOR;
                }
            }
        } else if (
            _application.validatedAt != 0 ||
            _application.rejectionAcceptedAt != 0
        ) {
            return ApplicationStatus.ENDED;
        } else if (
            _application.passedToValidationAt != 0 &&
            _application.validatedAt == 0
        ) {
            return ApplicationStatus.UNDER_VALIDATION;
        } else if (
            _application.realisationRejectedAt != 0 &&
            _application.passedToValidationAt == 0
        ) {
            return ApplicationStatus.NOT_ACCEPTED;
        } else if (_application.realisationAcceptedAt != 0) {
            return ApplicationStatus.ACCEPTED;
        } else if (
            _application.addedToReviewAt != 0 &&
            _application.realisationAcceptedAt == 0 &&
            _application.realisationRejectedAt == 0
        ) {
            return ApplicationStatus.UNDER_REVIEW;
        } else if (
            _application.nominationAcceptedAt != 0 &&
            _application.addedToReviewAt == 0
        ) {
            return ApplicationStatus.IN_PROGRESS;
        } else if (
            _application.hunter != ZERO_ADDRESS && _application.nominatedAt != 0
        ) {
            return ApplicationStatus.NOMINATED;
        } else {
            return ApplicationStatus.OPEN_TO_NOMINATION;
        }
    }

    struct Bounty {
        uint256 id;
        address creator;
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
        uint256[] applicationIds;
        uint256 nominationAcceptanceDeadline;
        string realisationProof;
        uint8 hunterDepositDecreasePerDayAfterAcceptance;
        uint8 hunterRewardDecreasePerDayAfterDeadline;
        Application application;
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
        uint256 nominatedAt;
        uint256 nominationAcceptedAt;
        uint256 addedToReviewAt;
        uint256 realisationAcceptedAt;
        uint256 realisationRejectedAt;
        uint256 rejectionAcceptedAt;
        uint256 passedToValidationAt;
        uint256 validatedAt;
        uint256 canceledAt;
        CanceledBy canceledBy;
        uint256 id;
    }

    mapping(address => mapping(uint256 => uint256))
        private applicationIdByBountyIdAndAddress;
    address public admin;
    uint256 private bountyId;
    uint256 private applicationId = 1;
    mapping(uint256 => Bounty) private bountyById;
    mapping(uint256 => Application) private applicationById;
    mapping(uint256 => address) private creatorByBountyId;
    mapping(uint256 => address) private hunterByBountyId;
    mapping(uint256 => address) private validatorByBountyId;
    mapping(address => User) private userByAddress;
    uint256[] private bountyIds;
    mapping(address => uint256[]) private bountyIdsByCreator;
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
        uint256 _minHunterDeposit,
        uint8 _refundDecreasePerDayAfterAcceptance,
        uint8 _rewardDecreasePerDayAfterDeadline
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
        require(
            _refundDecreasePerDayAfterAcceptance <= 100,
            "Refund decrease must be <= 100"
        );
        require(
            _rewardDecreasePerDayAfterDeadline <= 100,
            "Reward decrease must be <= 100"
        );

        Bounty memory bounty = Bounty(
            bountyId,
            msg.sender,
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
            new uint256[](0),
            0,
            "",
            _refundDecreasePerDayAfterAcceptance,
            _rewardDecreasePerDayAfterDeadline,
            Application(
                ZERO_ADDRESS,
                bountyId,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                CanceledBy.NONE,
                0
            )
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
        ApplicationStatus applicationStatus = getBountyApplicationStatus(
            bounty.application
        );
        require(
            applicationStatus == ApplicationStatus.OPEN_TO_NOMINATION ||
                applicationStatus == ApplicationStatus.NOMINATED,
            "Invalid application status"
        );
        require(bounty.creator != msg.sender, "Cannot apply for own bounty");
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
            applicationIdByBountyIdAndAddress[msg.sender][_bountyId] == 0,
            "Already applied"
        );

        applicationById[applicationId] = Application(
            msg.sender,
            _bountyId,
            _proposedDeadline,
            _proposedReward,
            _validUntil,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            CanceledBy.NONE,
            applicationId
        );
        applicationIdByBountyIdAndAddress[msg.sender][
            _bountyId
        ] = applicationId;
        bounty.applicationIds.push(applicationId);
        applicationId++;
    }

    function nominateApplication(uint256 _applicationId) external {
        require(_applicationId != 0, "Invalid application id");
        Application storage application = applicationById[_applicationId];
        Bounty storage bounty = bountyById[application.bountyId];
        require(
            getBountyApplicationStatus(bounty.application) ==
                ApplicationStatus.OPEN_TO_NOMINATION,
            "Invalid application status"
        );
        require(bounty.creator == msg.sender, "Not bounty creator");
        require(
            application.validUntil >= block.timestamp,
            "Application no longer valid"
        );
        // TODO : Adjust creator balances regarding application proposed reward
        application.nominatedAt = block.timestamp;
        bounty.application = application;
        bounty.nominationAcceptanceDeadline =
            block.timestamp +
            bounty.nominationAcceptanceTime;
    }

    function acceptNomination(uint256 _applicationId) external {
        Application storage application = applicationById[_applicationId];
        require(application.hunter == msg.sender, "Not nominated hunter");
        Bounty storage bounty = bountyById[application.bountyId];
        require(
            getBountyApplicationStatus(bounty.application) ==
                ApplicationStatus.NOMINATED,
            "Invalid application status"
        );
        require(
            bounty.nominationAcceptanceDeadline >= block.timestamp,
            "Acceptance deadline passed"
        );
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
        application.nominationAcceptedAt = block.timestamp;
        bounty.hunterReward = application.proposedReward;
        bounty.deadline = application.proposedDeadline;
    }

    function cancelApplication(uint256 _applicationId) external {
        Application storage application = applicationById[_applicationId];
        require(application.hunter == msg.sender, "Not bounty hunter");
        ApplicationStatus status = getBountyApplicationStatus(application);
        application.canceledAt = block.timestamp;
        application.canceledBy = CanceledBy.HUNTER;
        if (status == ApplicationStatus.OPEN_TO_NOMINATION) {} else if (
            status == ApplicationStatus.NOMINATED
        ) {
            Bounty storage bounty = bountyById[application.bountyId];
            bounty.nominationAcceptanceDeadline = 0;
            userByAddress[msg.sender].canceledAfterNomination += 1;
        } else if (status == ApplicationStatus.ACCEPTED) {
            Bounty storage bounty = bountyById[application.bountyId];
            bounty.nominationAcceptanceDeadline = 0;
            userByAddress[msg.sender].canceledAfterAcceptance += 1;

            uint256 daysSinceAcceptance = getDaysFromNow(
                application.nominationAcceptedAt
            );
            // +1: 0 days counts as 1
            uint256 percentageLostByHunter = (daysSinceAcceptance + 1) *
                bounty.hunterDepositDecreasePerDayAfterAcceptance;
            if (percentageLostByHunter > 100) {
                percentageLostByHunter = 100;
            }

            uint256 minHunterDeposit = bounty.minHunterDeposit;
            uint256 depositLostByHunter = (percentageLostByHunter *
                minHunterDeposit *
                100) / 10_000;
            uint256 depositReturnedToHunter = minHunterDeposit -
                depositLostByHunter;

            address creator = bounty.creator;
            address token = bounty.token;
            uint256 validatorReward = bounty.validatorReward;
            uint256 hunterReward = bounty.hunterReward;
            uint256 creatorAmount = validatorReward +
                hunterReward +
                depositLostByHunter;

            claimableTokenBalanceByUser[creator][token] += creatorAmount;
            claimableTokenBalanceByUser[msg.sender][token] += (validatorReward +
                depositReturnedToHunter);
            tokenBalanceByUser[msg.sender][token] -= (validatorReward +
                depositLostByHunter);
        } else {
            revert("Invalid application status");
        }
    }

    function cancelApplicationNomination(uint256 _applicationId) external {
        Application storage application = applicationById[_applicationId];
        require(
            getBountyApplicationStatus(application) ==
                ApplicationStatus.NOMINATED,
            "Invalid application status"
        );
        Bounty storage bounty = bountyById[application.bountyId];
        require(bounty.creator == msg.sender, "Not bounty creator");
        application.canceledAt = block.timestamp;
        application.canceledBy = CanceledBy.CREATOR;
        bounty.nominationAcceptanceDeadline = 0;
    }

    function addApplicationToReview(
        uint256 _applicationId,
        string calldata _realisationProof
    ) external {
        Application storage application = applicationById[_applicationId];
        require(
            getBountyApplicationStatus(application) ==
                ApplicationStatus.IN_PROGRESS,
            "Invalid application status"
        );
        require(application.hunter == msg.sender, "Not bounty hunter");
        Bounty storage bounty = bountyById[application.bountyId];
        // Check probrably redundant - Application may be added after deadline
        // require(bounty.deadline >= block.timestamp, "Deadline passed");
        application.addedToReviewAt = block.timestamp;
        bounty.realisationProof = _realisationProof;
    }

    function getBountyApplications(
        uint256 _bountyId
    ) external view returns (Application[] memory) {
        uint256[] memory applicationIds = bountyById[_bountyId].applicationIds;
        uint256 applicationsCount = applicationIds.length;
        Application[] memory applications = new Application[](
            applicationsCount
        );
        for (uint256 i; i < applicationsCount; i++) {
            applications[i] = applicationById[i];
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

    function acceptApplicationCompletion(uint256 _applicationId) external {
        Application storage application = applicationById[_applicationId];
        require(
            getBountyApplicationStatus(application) ==
                ApplicationStatus.UNDER_REVIEW,
            "Invalid application status"
        );
        Bounty storage bounty = bountyById[application.bountyId];

        require(bounty.creator == msg.sender, "Not bounty creator");

        address hunter = application.hunter;
        address token = bounty.token;
        uint256 validatorReward = bounty.validatorReward;
        uint256 hunterReward = bounty.hunterReward;
        uint256 hunterDeposits = bounty.minHunterDeposit + validatorReward;
        uint256 hunterAmount = hunterReward + hunterDeposits;

        // TODO: calc correct amounts based on duration after deadline
        // TODO: Failed => Find why?
        claimableTokenBalanceByUser[hunter][token] += hunterAmount;
        tokenBalanceByUser[hunter][token] -= hunterDeposits;
        claimableTokenBalanceByUser[msg.sender][token] += validatorReward;
        tokenBalanceByUser[msg.sender][token] -= (validatorReward +
            hunterAmount);
        application.realisationAcceptedAt = block.timestamp;
    }

    function rejectApplicationRealisation(uint256 _bountyId) external {
        // Check which approach is more gase efficient => here we get bounty by id instead of getting application first
        Bounty storage bounty = bountyById[_bountyId];
        require(bounty.creator == msg.sender, "Not bounty creator");
        require(
            getBountyApplicationStatus(bounty.application) ==
                ApplicationStatus.UNDER_REVIEW,
            "Invalid application status"
        );
        bounty.application.realisationRejectedAt = block.timestamp;
    }

    function acceptApplicationCompletionRejection(
        uint256 _applicationId
    ) external {
        Application storage application = applicationById[_applicationId];
        require(application.hunter == msg.sender, "Not bounty hunter");
        require(
            getBountyApplicationStatus(application) ==
                ApplicationStatus.NOT_ACCEPTED,
            "Invalid application status"
        );
        Bounty storage bounty = bountyById[application.bountyId];

        address creator = bounty.creator;
        address token = bounty.token;
        uint256 validatorReward = bounty.validatorReward;
        uint256 hunterReward = bounty.hunterReward;
        uint256 minHunterDeposit = bounty.minHunterDeposit;
        uint256 creatorAmount = validatorReward +
            hunterReward +
            minHunterDeposit;

        // CALC based on time after deadline
        claimableTokenBalanceByUser[creator][token] += creatorAmount;
        tokenBalanceByUser[creator][token] -= (validatorReward + hunterReward);
        claimableTokenBalanceByUser[msg.sender][token] += validatorReward;
        tokenBalanceByUser[msg.sender][token] -= (validatorReward +
            minHunterDeposit);

        application.rejectionAcceptedAt = block.timestamp;
    }

    function passApplicationToValidation(uint256 _applicationId) external {
        Application storage application = applicationById[_applicationId];
        require(application.hunter == msg.sender, "Not bounty hunter");
        require(
            getBountyApplicationStatus(application) ==
                ApplicationStatus.NOT_ACCEPTED,
            "Invalid application status"
        );
        application.passedToValidationAt = block.timestamp;
    }

    function updateApplication(
        uint256 _applicationId,
        uint256 _proposedDeadline,
        uint256 _proposedReward,
        uint256 _validUntil
    ) external {
        require(
            _proposedReward != 0 || _proposedDeadline != 0 || _validUntil != 0,
            "Must edit at least one field"
        );

        Application storage application = applicationById[_applicationId];
        require(application.hunter == msg.sender, "Not bounty hunter");
        require(
            getBountyApplicationStatus(application) ==
                ApplicationStatus.OPEN_TO_NOMINATION,
            "Invalid application status"
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

    // TODO: move this method to some library
    function getDaysFromNow(
        uint256 _timestamp
    ) internal view returns (uint256) {
        uint256 difference = _absoluteDifference(_timestamp, block.timestamp);
        return difference / 1 days;
    }

    function _absoluteDifference(
        uint256 a,
        uint256 b
    ) private pure returns (uint256) {
        return a >= b ? a - b : b - a;
    }
}
