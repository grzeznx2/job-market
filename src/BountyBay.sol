pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BountyBay {
    address constant ZERO_ADDRESS = address(0);
    uint256 public minBountyNameLength = 3;
    uint256 public maxBountyNameLength = 1000;
    uint256 public minBountyDescriptionLength = 3;
    uint256 public maxBountyDescriptionLength = 1000;
    uint256 public minBountyAcceptanceCriteriaLength = 3;
    uint256 public maxBountyAcceptanceCriteriaLength = 1000;

    enum BountyStatus {
        OPEN_FOR_APPLICATIONS,
        REALISATION_IN_PROGRESS,
        REALISATION_UNDER_REVIEW,
        REALISATION_ACCEPTED,
        REALISATION_NOT_ACCEPTED,
        REALISATION_UNDER_VALIDATION,
        REALISATION_ENDED,
        CANCELED_BEFORE_REALISATION,
        REALISATION_CANCELED_BY_HUNTER,
        REALISATION_CANCELED_BY_CREATOR
    }

    enum ApplicationStatus {
        OPEN,
        ACCEPTED,
        CANCELED,
        EXPIRED
    }

    enum RealisationStatus {
        IN_PROGRESS,
        UNDER_REVIEW,
        ACCEPTED,
        NOT_ACCEPTED,
        UNDER_VALIDATION,
        ENDED,
        CANCELED_BY_HUNTER,
        CANCELED_BY_CREATOR
    }

    enum CanceledBy {
        NONE,
        HUNTER,
        CREATOR
    }

    function getApplicationStatus(
        Application memory _application
    ) internal view returns (ApplicationStatus) {
        if (_application.canceledAt != 0) {
            return ApplicationStatus.CANCELED;
        } else if (_application.validUntil < block.timestamp) {
            return ApplicationStatus.EXPIRED;
        } else {
            return ApplicationStatus.OPEN;
        }
    }

    function getRealisationStatus(
        Realisation memory _realisation
    ) internal pure returns (RealisationStatus) {
        if (_realisation.canceledAt != 0) {
            if (_realisation.canceledBy == CanceledBy.HUNTER) {
                return RealisationStatus.CANCELED_BY_HUNTER;
            } else {
                return RealisationStatus.CANCELED_BY_CREATOR;
            }
        } else if (
            _realisation.validatedAt != 0 ||
            _realisation.rejectionAcceptedAt != 0
        ) {
            return RealisationStatus.ENDED;
        } else if (
            _realisation.passedToValidationAt != 0 &&
            _realisation.validatedAt == 0
        ) {
            return RealisationStatus.UNDER_VALIDATION;
        } else if (
            _realisation.realisationRejectedAt != 0 &&
            _realisation.passedToValidationAt == 0
        ) {
            return RealisationStatus.NOT_ACCEPTED;
        } else if (_realisation.realisationAcceptedAt != 0) {
            return RealisationStatus.ACCEPTED;
        } else if (
            _realisation.addedToReviewAt != 0 &&
            _realisation.realisationAcceptedAt == 0 &&
            _realisation.realisationRejectedAt == 0
        ) {
            return RealisationStatus.UNDER_REVIEW;
        } else return RealisationStatus.IN_PROGRESS;
    }

    function getBountyStatus(
        Bounty memory _bounty
    ) internal view returns (BountyStatus) {
        RealisationStatus realisationStatus = getRealisationStatus(
            _bounty.realisation
        );

        if (realisationStatus == RealisationStatus.CANCELED_BY_CREATOR) {
            return BountyStatus.REALISATION_CANCELED_BY_CREATOR;
        } else if (realisationStatus == RealisationStatus.CANCELED_BY_HUNTER) {
            return BountyStatus.REALISATION_CANCELED_BY_HUNTER;
        } else if (realisationStatus == RealisationStatus.ENDED) {
            return BountyStatus.REALISATION_ENDED;
        } else if (realisationStatus == RealisationStatus.UNDER_VALIDATION) {
            return BountyStatus.REALISATION_UNDER_VALIDATION;
        } else if (realisationStatus == RealisationStatus.NOT_ACCEPTED) {
            return BountyStatus.REALISATION_NOT_ACCEPTED;
        } else if (realisationStatus == RealisationStatus.ACCEPTED) {
            return BountyStatus.REALISATION_ACCEPTED;
        } else if (realisationStatus == RealisationStatus.IN_PROGRESS) {
            return BountyStatus.REALISATION_IN_PROGRESS;
        }

        if (_bounty.canceledAt != 0) {
            return BountyStatus.CANCELED_BEFORE_REALISATION;
            // TODO: Should also check for deadline or other timestamps here
        } else return BountyStatus.OPEN_FOR_APPLICATIONS;
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
        uint256 reviewPeriodTime;
        uint256 hunterReward;
        uint256 validatorReward;
        uint256 minHunterReputation;
        uint256 minHunterDeposit;
        uint256[] applicationIds;
        uint8 hunterDepositDecreasePerDayAfterAcceptance;
        uint8 hunterRewardDecreasePerDayAfterDeadline;
        // TODO: implement bounty cancellation
        uint256 canceledAt;
        Application application;
        Realisation realisation;
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
        uint256 canceledRealisationsCount;
    }

    struct Application {
        address hunter;
        uint256 bountyId;
        uint256 proposedDeadline;
        uint256 proposedReward;
        uint256 validUntil;
        uint256 acceptedAt;
        uint256 canceledAt;
        CanceledBy canceledBy;
        uint256 id;
    }

    struct Realisation {
        address hunter;
        uint256 bountyId;
        uint256 id;
        uint256 startedAt;
        uint256 addedToReviewAt;
        uint256 realisationAcceptedAt;
        uint256 realisationRejectedAt;
        uint256 rejectionAcceptedAt;
        uint256 passedToValidationAt;
        uint256 validatedAt;
        uint256 canceledAt;
        CanceledBy canceledBy;
        string realisationProof;
    }

    mapping(address => mapping(uint256 => uint256))
        private applicationIdByBountyIdAndAddress;
    address public admin;
    uint256 private bountyId;
    uint256 private applicationId = 1;
    mapping(uint256 => Bounty) private bountyById;
    mapping(uint256 => Application) private applicationById;
    mapping(uint256 => Realisation) private realisationById;
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
        uint256 _reviewPeriodTime,
        uint256 _hunterReward,
        uint256 _validatorReward,
        uint256 _minHunterReputation,
        uint256 _minHunterDeposit,
        uint8 _refundDecreasePerDayAfterAcceptance,
        uint8 _rewardDecreasePerDayAfterDeadline
    ) external {
        require(_deadline > block.timestamp, "Deadline must be in the future");
        uint256 nameLength = bytes(_name).length;
        uint256 descriptionLength = bytes(_description).length;
        uint256 acceptanceCriteriaLength = bytes(_acceptanceCriteria).length;
        require(nameLength >= minBountyNameLength, "Name too short");
        require(nameLength <= minBountyNameLength, "Name too long");
        require(
            descriptionLength >= minBountyDescriptionLength,
            "Description too short"
        );
        require(
            descriptionLength <= minBountyDescriptionLength,
            "Description too long"
        );
        require(
            acceptanceCriteriaLength >= minBountyAcceptanceCriteriaLength,
            "AcceptanceCriteria too short"
        );
        require(
            acceptanceCriteriaLength <= minBountyAcceptanceCriteriaLength,
            "AcceptanceCriteria too long"
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
            _reviewPeriodTime,
            _hunterReward,
            _validatorReward,
            _minHunterReputation,
            _minHunterDeposit,
            new uint256[](0),
            _refundDecreasePerDayAfterAcceptance,
            _rewardDecreasePerDayAfterDeadline,
            0,
            Application(
                ZERO_ADDRESS,
                bountyId,
                0,
                0,
                0,
                0,
                0,
                CanceledBy.NONE,
                0
            ),
            Realisation(
                ZERO_ADDRESS,
                bountyId,
                // Realisation.id probably unnecessary, because it's always equall to bountyId
                bountyId,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                CanceledBy.NONE,
                ""
            )
        );

        _lockTokens(_token, _validatorReward + _hunterReward);
        bountyById[bountyId] = bounty;
        bountyIdsByCreator[msg.sender].push(bountyId);
        bountyIds.push(bountyId);
        bountyId++;
    }

    function applyForBounty(
        uint256 _bountyId,
        uint256 _proposedDeadline,
        uint256 _proposedReward,
        uint256 _validUntil,
        bool _addMissingAmount
    ) external {
        User memory user = userByAddress[msg.sender];
        Bounty storage bounty = bountyById[_bountyId];
        BountyStatus bountyStatus = getBountyStatus(bounty);
        require(
            bountyStatus == BountyStatus.OPEN_FOR_APPLICATIONS,
            "Ivalid bounty status"
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
        require(_validUntil >= block.timestamp, "Must be in the future");

        require(
            applicationIdByBountyIdAndAddress[msg.sender][_bountyId] == 0,
            "Already applied"
        );

        if (_addMissingAmount) {
            address token = bounty.token;
            uint256 hunterClaimableBalance = claimableTokenBalanceByUser[
                msg.sender
            ][token];
            if (bounty.minHunterDeposit > hunterClaimableBalance) {
                bool success = IERC20(token).transferFrom(
                    msg.sender,
                    address(this),
                    bounty.minHunterDeposit - hunterClaimableBalance
                );
                require(success, "Error transfering funds");
            }
        }

        applicationById[applicationId] = Application(
            msg.sender,
            _bountyId,
            _proposedDeadline,
            _proposedReward,
            _validUntil,
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

    function acceptApplication(uint256 _applicationId) external {
        Application storage application = applicationById[_applicationId];
        require(
            getApplicationStatus(application) == ApplicationStatus.OPEN,
            "Invalid application status"
        );
        Bounty storage bounty = bountyById[application.bountyId];
        require(
            getBountyStatus(bounty) == BountyStatus.OPEN_FOR_APPLICATIONS,
            "Invalid bounty status"
        );
        require(bounty.creator == msg.sender, "Not bounty creator");
        uint256 claimableHunterAmount = claimableTokenBalanceByUser[
            application.hunter
        ][bounty.token];
        require(
            claimableHunterAmount >= bounty.minHunterDeposit,
            "Claimable hunter amount too low"
        );
        _moveTokensFromClaimableToLocked(
            application.hunter,
            bounty.token,
            bounty.minHunterDeposit
        );
        application.acceptedAt = block.timestamp;
        bounty.realisation.hunter = application.hunter;
        bounty.realisation.startedAt = block.timestamp;
        bounty.application = application;
        // The original bounty.hunterReward and bounty.deadline won't be overriden, we store the new values in bounty.application
        if (application.proposedReward > bounty.hunterReward) {
            _lockTokens(
                bounty.token,
                application.proposedReward - bounty.hunterReward
            );
        } else if (application.proposedReward < bounty.hunterReward) {
            _moveTokensFromLockedToClaimable(
                msg.sender,
                bounty.token,
                bounty.hunterReward - application.proposedReward
            );
        }
    }

    function cancelApplication(uint256 _applicationId) external {
        Application storage application = applicationById[_applicationId];
        require(application.hunter == msg.sender, "Not bounty hunter");
        require(
            getApplicationStatus(application) == ApplicationStatus.OPEN,
            "Invalid application status"
        );
        application.canceledAt = block.timestamp;
    }

    function cancelRealisation(uint256 _realisationId) external {
        Realisation storage realisation = realisationById[_realisationId];
        require(realisation.hunter == msg.sender, "Not bounty hunter");
        RealisationStatus status = getRealisationStatus(realisation);
        require(
            status == RealisationStatus.IN_PROGRESS,
            "Invalid realisation status"
        );
        realisation.canceledAt = block.timestamp;
        realisation.canceledBy = CanceledBy.HUNTER;
        Bounty storage bounty = bountyById[realisation.bountyId];
        userByAddress[msg.sender].canceledRealisationsCount += 1;

        uint256 daysSinceAcceptance = getDaysFromNow(realisation.startedAt);
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
        uint256 hunterReward = bounty.application.proposedReward;
        uint256 creatorAmount = validatorReward +
            hunterReward +
            depositLostByHunter;

        claimableTokenBalanceByUser[creator][token] += creatorAmount;
        claimableTokenBalanceByUser[msg.sender][token] += (validatorReward +
            depositReturnedToHunter);
        tokenBalanceByUser[msg.sender][token] -= (validatorReward +
            depositLostByHunter);
    }

    function addRealisationToReview(
        uint256 _realisationId,
        string calldata _realisationProof
    ) external {
        Realisation storage realisation = realisationById[_realisationId];
        require(
            getRealisationStatus(realisation) == RealisationStatus.IN_PROGRESS,
            "Invalid realisation status"
        );
        require(realisation.hunter == msg.sender, "Not bounty hunter");
        Bounty storage bounty = bountyById[realisation.bountyId];
        realisation.addedToReviewAt = block.timestamp;
        realisation.realisationProof = _realisationProof;
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

    function acceptRealisation(uint256 _realisationId) external {
        Realisation storage realisation = realisationById[_realisationId];
        require(
            getRealisationStatus(realisation) == RealisationStatus.UNDER_REVIEW,
            "Invalid realisation status"
        );
        Bounty storage bounty = bountyById[realisation.bountyId];

        require(bounty.creator == msg.sender, "Not bounty creator");

        address hunter = realisation.hunter;
        address token = bounty.token;
        uint256 validatorReward = bounty.validatorReward;
        uint256 hunterReward = bounty.application.proposedReward;
        uint256 deadline = bounty.application.proposedDeadline;
        uint256 hunterDeposits = bounty.minHunterDeposit + validatorReward;

        uint256 rewardPercentageLostByHunter;
        if (realisation.addedToReviewAt > deadline) {
            uint256 daysAfterDeadline = _calcDays(
                realisation.addedToReviewAt - deadline
            );

            rewardPercentageLostByHunter =
                (daysAfterDeadline + 1) *
                bounty.hunterRewardDecreasePerDayAfterDeadline;
            if (rewardPercentageLostByHunter > 100) {
                rewardPercentageLostByHunter = 100;
            }
        }

        uint256 rewardLostByHunter = (rewardPercentageLostByHunter *
            hunterReward *
            100) / 10_000;
        uint256 finalHunterReward = hunterReward - rewardLostByHunter;

        uint256 hunterAmount = finalHunterReward + hunterDeposits;

        uint256 creatorAmount = validatorReward + rewardLostByHunter;

        // TODO: Failed => Find why?
        claimableTokenBalanceByUser[hunter][token] += hunterAmount; // OK
        tokenBalanceByUser[hunter][token] -= hunterDeposits; // OK
        claimableTokenBalanceByUser[msg.sender][token] += creatorAmount;
        tokenBalanceByUser[msg.sender][token] -= (validatorReward +
            hunterAmount);
        realisation.realisationAcceptedAt = block.timestamp;
    }

    function rejectRealisation(uint256 _realisationId) external {
        Realisation storage realisation = realisationById[_realisationId];
        require(
            getRealisationStatus(realisation) == RealisationStatus.UNDER_REVIEW,
            "Invalid realisation status"
        );

        require(
            bountyById[realisation.bountyId].creator == msg.sender,
            "Not bounty creator"
        );
        realisation.realisationRejectedAt = block.timestamp;
    }

    function acceptRealisationRejection(uint256 _realisationId) external {
        Realisation storage realisation = realisationById[_realisationId];
        require(realisation.hunter == msg.sender, "Not bounty hunter");
        require(
            getRealisationStatus(realisation) == RealisationStatus.NOT_ACCEPTED,
            "Invalid realisation status"
        );
        Bounty storage bounty = bountyById[realisation.bountyId];

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

        realisation.rejectionAcceptedAt = block.timestamp;
    }

    function passRealisationToValidation(uint256 _realisationId) external {
        Realisation storage realisation = realisationById[_realisationId];
        require(realisation.hunter == msg.sender, "Not bounty hunter");
        require(
            getRealisationStatus(realisation) == RealisationStatus.NOT_ACCEPTED,
            "Invalid realisation status"
        );
        realisation.passedToValidationAt = block.timestamp;
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
            getApplicationStatus(application) ==
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

    function _calcDays(uint256 _time) private pure returns (uint256) {
        return _time / 1 days;
    }

    function _lockTokens(address _token, uint256 _amount) private {
        if (claimableTokenBalanceByUser[msg.sender][_token] >= _amount) {
            claimableTokenBalanceByUser[msg.sender][_token] -= _amount;
        } else {
            bool success = IERC20(_token).transferFrom(
                msg.sender,
                address(this),
                _amount
            );
            require(success, "Error transfering funds");
        }
        tokenBalanceByUser[msg.sender][_token] += _amount;
    }

    function _moveTokensFromClaimableToLocked(
        address _user,
        address _token,
        uint256 _amount
    ) private {
        claimableTokenBalanceByUser[_user][_token] -= _amount;
        tokenBalanceByUser[_user][_token] += _amount;
    }

    function _moveTokensFromLockedToClaimable(
        address _user,
        address _token,
        uint256 _amount
    ) private {
        claimableTokenBalanceByUser[_user][_token] += _amount;
        tokenBalanceByUser[_user][_token] -= _amount;
    }
}
