
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract WalletSafetyRating {
    struct WalletProfile {
        uint256 totalRatings;    // Sum of all ratings
        uint256 ratingCount;     // Number of ratings
        uint256 flagCount;       // Total number of flags
        uint256 lastUpdated;     // Timestamp of the last interaction
        bool exists;             // Whether this profile exists
        string safetyLevel;      // Safety level of the wallet
    }

    struct UserReputation {
        uint256 score;           // Reputation score of the user
        uint256 validFlags;      // Number of valid flags submitted
        uint256 invalidFlags;    // Number of invalid flags submitted
    }

    // Wallet profiles and user reputations
    mapping(address => WalletProfile) private profiles;
    mapping(address => UserReputation) private userReputations;
    
    // Mapping to track user ratings and flags
    mapping(address => mapping(address => uint256)) private userRatings; // Tracks user rating value
    mapping(address => mapping(address => bool)) private hasFlagged;

    // Admin role for dispute handling
    address public admin;

    // Reputation threshold and safety levels
    uint256 public reputationThreshold = 10;
    uint256 public ratingExpiry = 30 days; // Ratings expire after 30 days

    // Events
    event WalletRated(address indexed wallet, address indexed rater, uint256 rating, string comment);
    event WalletFlagged(address indexed wallet, address indexed flagger, string reason);
    event ReputationThresholdBreached(address indexed wallet);
    event WalletSafetyLevelUpdated(address indexed wallet, string newLevel);

    // Modifier to check valid wallet address
    modifier validWallet(address _wallet) {
        require(_wallet != address(0), "Invalid wallet address");
        _;
    }

    // Modifier for admin-only actions
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can perform this action");
        _;
    }

    // Constructor to set admin
    constructor() {
        admin = msg.sender;
    }

    // Function to rate a wallet
    function rateWallet(address _wallet, uint256 _rating, string calldata _comment)
        external
        validWallet(_wallet)
    {
        require(_rating >= 1 && _rating <= 100, "Rating must be between 1 and 100");

        WalletProfile storage profile = profiles[_wallet];

        // If this is the first interaction with the wallet
        if (!profile.exists) {
            profile.exists = true;
        }

        // Update or add the user's rating
        if (userRatings[_wallet][msg.sender] > 0) {
            uint256 previousRating = userRatings[_wallet][msg.sender];
            profile.totalRatings = profile.totalRatings - previousRating + _rating;
        } else {
            profile.totalRatings += _rating;
            profile.ratingCount += 1;
        }

        profile.lastUpdated = block.timestamp;
        userRatings[_wallet][msg.sender] = _rating;

        updateSafetyLevel(_wallet);

        emit WalletRated(_wallet, msg.sender, _rating, _comment);
    }

    // Function to flag a wallet
    function flagWallet(address _wallet, string calldata _reason)
        external
        validWallet(_wallet)
    {
        require(bytes(_reason).length <= 256, "Reason too long"); // Limit reason length
        require(!hasFlagged[_wallet][msg.sender], "You have already flagged this wallet");

        WalletProfile storage profile = profiles[_wallet];

        // If this is the first interaction with the wallet
        if (!profile.exists) {
            profile.exists = true;
        }

        profile.flagCount += 1;
        profile.lastUpdated = block.timestamp;
        hasFlagged[_wallet][msg.sender] = true;

        // Update user reputation
        userReputations[msg.sender].score += 1;
        userReputations[msg.sender].validFlags += 1;

        emit WalletFlagged(_wallet, msg.sender, _reason);

        // Check if reputation threshold is breached
        if (profile.flagCount >= reputationThreshold) {
            emit ReputationThresholdBreached(_wallet);
        }

        updateSafetyLevel(_wallet);
    }

    // Function to get a wallet's average score
    function getWalletScore(address _wallet) public view returns (uint256) {
        WalletProfile memory profile = profiles[_wallet];
        require(profile.exists, "Wallet profile does not exist");

        if (profile.ratingCount == 0) {
            return 0; // No ratings yet
        }
        return profile.totalRatings / profile.ratingCount; // Calculate average
    }

    // Function to get full wallet profile
    function getWalletProfile(address _wallet)
        external
        view
        returns (
            uint256 averageScore,
            uint256 flagCount,
            uint256 ratingCount,
            string memory safetyLevel
        )
    {
        WalletProfile memory profile = profiles[_wallet];
        require(profile.exists, "Wallet profile does not exist");

        averageScore = (profile.ratingCount == 0) ? 0 : profile.totalRatings / profile.ratingCount;
        flagCount = profile.flagCount;
        ratingCount = profile.ratingCount;
        safetyLevel = profile.safetyLevel;
    }

    // Admin-only function to reset a wallet's profile (e.g., in case of disputes)
    function resetWalletProfile(address _wallet) external onlyAdmin validWallet(_wallet) {
        delete profiles[_wallet];
    }

    // Function to transfer admin role
    function transferAdminRole(address newAdmin) external onlyAdmin validWallet(newAdmin) {
        admin = newAdmin;
    }

    // Admin-only function to update reputation threshold
    function updateReputationThreshold(uint256 newThreshold) external onlyAdmin {
        reputationThreshold = newThreshold;
    }

    // Function to update the safety level of a wallet
    function updateSafetyLevel(address _wallet) internal {
        WalletProfile storage profile = profiles[_wallet];
        require(profile.exists, "Wallet profile does not exist");

        if (profile.flagCount >= reputationThreshold) {
            profile.safetyLevel = "Unsafe";
        } else if (profile.ratingCount > 0 && getWalletScore(_wallet) >= 80) {
            profile.safetyLevel = "Safe";
        } else {
            profile.safetyLevel = "Caution";
        }

        emit WalletSafetyLevelUpdated(_wallet, profile.safetyLevel);
    }

    // Function to retrieve user reputation
    function getUserReputation(address user)
        external
        view
        returns (uint256 score, uint256 validFlags, uint256 invalidFlags)
    {
        UserReputation memory reputation = userReputations[user];
        score = reputation.score;
        validFlags = reputation.validFlags;
        invalidFlags = reputation.invalidFlags;
    }
}
