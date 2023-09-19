// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IPancakeRouter} from "./interfaces/IPancakeRouter.sol";
import {IPancakeFactory} from "./interfaces/IPancakeFactory.sol";

/**
 * @title CryptoRealEstate
 * @dev ERC20 token contract representing CryptoRealEstate.
 */
contract CryptoRealEstate is ERC20, Ownable {
    using Address for address payable;
    using SafeERC20 for IERC20;

    uint256 private constant INITIAL_TOTAL_SUPPLY = 100000000 * 10 ** 18;

    IPancakeRouter private immutable pancakeRouter;
    address private immutable weth;
    address public immutable dex;

    bool private tradingOpened;
    bool private inSwap = false;

    address public marketingAddress;

    uint8 public buyTaxFeePercent;
    uint8 public transferTaxFeePercent;
    uint8 public sellTaxFeePercent;

    uint256 private sThreshold = (INITIAL_TOTAL_SUPPLY * 3) / 10000; // 0.03% of initial total supply
    mapping(address => bool) public whiteList;

    /**
     * @dev Emitted when the token contract is initialized.
     * @param name The name of the token.
     * @param symbol The symbol of the token.
     * @param owner The address of the contract owner.
     * @param marketingAddress The address for marketing purposes.
     * @param initialTokenReceiver The address of the initial token receiver.
     * @param pancakeRouter The address of the PancakeSwap router.
     * @param buyTaxFeePercent The buy tax fee percentage.
     * @param transferTaxFeePercent The transfer tax fee percentage.
     * @param sellTaxFeePercent The sell tax fee percentage.
     */
    event TokenInitialized(
        string name,
        string symbol,
        address owner,
        address marketingAddress,
        address initialTokenReceiver,
        IPancakeRouter pancakeRouter,
        uint256 buyTaxFeePercent,
        uint256 transferTaxFeePercent,
        uint256 sellTaxFeePercent
    );

    /**
     * @dev Emitted when the swap amount is changed.
     * @param oldAmount The old swap amount.
     * @param newAmount The new swap amount.
     */
    event SwapAmountChanged(uint256 oldAmount, uint256 newAmount);

    /**
     * @dev Emitted when an address is added to the whitelist.
     * @param _address The address added to the whitelist.
     */
    event AddedToWhitelist(address _address);

    /**
     * @dev Emitted when an address is removed from the whitelist.
     * @param _address The address removed from the whitelist.
     */
    event RemovedFromWhitelist(address _address);

    /**
     * @dev Emitted when the buy tax fee percentage is changed.
     * @param oldPercent The old buy tax fee percentage.
     * @param newPercent The new buy tax fee percentage.
     */
    event BuyTaxFeePercentChanged(uint256 oldPercent, uint256 newPercent);

    /**
     * @dev Emitted when the transfer tax fee percentage is changed.
     * @param oldPercent The old transfer tax fee percentage.
     * @param newPercent The new transfer tax fee percentage.
     */
    event TransferTaxFeePercentChanged(uint256 oldPercent, uint256 newPercent);

    /**
     * @dev Emitted when the sell tax fee percentage is changed.
     * @param oldPercent The old sell tax fee percentage.
     * @param newPercent The new sell tax fee percentage.
     */
    event SellTaxFeePercentChanged(uint256 oldPercent, uint256 newPercent);

    /**
     * @dev Emitted when the treasury address is changed.
     * @param oldAddress The old treasury address.
     * @param newAddress The new treasury address.
     */
    event TreasuryChanged(address oldAddress, address newAddress);

    /**
     * @dev Emitted when trading is opened.
     * @param timestamp The timestamp when trading was opened.
     */
    event TradingOpened(uint256 timestamp);

    /**
     * @dev Emitted when tokens are withdrawn from the contract.
     * @param to The address where the tokens are withdrawn to.
     * @param tokenAddress The address of the token being withdrawn.
     * @param amount The amount of tokens being withdrawn.
     */
    event WithdrawedToken(address to, address tokenAddress, uint256 amount);

    /**
     * @dev Emitted when BNB is withdrawn from the contract.
     * @param to The address where BNB is withdrawn to.
     * @param amount The amount of BNB being withdrawn.
     */
    event WithdrawedBNB(address to, uint256 amount);

    /**
     * @dev Modifier to lock the swap functionality during certain operations.
     */
    modifier lockTheSwap() {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        address _owner,
        address _marketingAddress,
        address _initialTokenReceiver,
        IPancakeRouter _pancakeRouter,
        uint8 _buyTaxFeePercent,
        uint8 _transferTaxFeePercent,
        uint8 _sellTaxFeePercent
    ) ERC20(_name, _symbol) {
        require(bytes(_name).length > 0, "Token name must not be empty");
        require(bytes(_symbol).length > 0, "Token symbol must not be empty");
        require(_owner != address(0), "Invalid owner address");
        require(_marketingAddress != address(0), "Invalid treasury address");
        require(
            _initialTokenReceiver != address(0),
            "Invalid initial token receiver address"
        );
        require(
            address(_pancakeRouter) != address(0),
            "Invalid pancakeRouter address"
        );
        require(_buyTaxFeePercent <= 3, "Unpossible fee amount");
        require(_transferTaxFeePercent <= 3, "Unpossible fee amount");
        require(_sellTaxFeePercent <= 9, "Unpossible fee amount");
        _mint(_initialTokenReceiver, INITIAL_TOTAL_SUPPLY);
        _transferOwnership(_owner);
        marketingAddress = _marketingAddress;
        pancakeRouter = _pancakeRouter;
        buyTaxFeePercent = _buyTaxFeePercent;
        transferTaxFeePercent = _transferTaxFeePercent;
        sellTaxFeePercent = _sellTaxFeePercent;
        address _weth = _pancakeRouter.WETH();
        weth = _weth;
        address pair = IPancakeFactory(_pancakeRouter.factory()).createPair(
            address(this),
            _weth
        );
        dex = pair;
        _approve(address(this), address(_pancakeRouter), type(uint256).max);
        whiteList[address(this)] = true;
        emit TokenInitialized(
            _name,
            _symbol,
            _owner,
            _marketingAddress,
            _initialTokenReceiver,
            _pancakeRouter,
            _buyTaxFeePercent,
            _transferTaxFeePercent,
            _sellTaxFeePercent
        );
    }

    receive() external payable {}

    /**
     * @dev Withdraws the BNB balance from the contract.
     */
    function withdrawBNB() external onlyOwner {
        uint256 amount = address(this).balance;
        address payable to = payable(msg.sender);
        to.sendValue(amount);
        emit WithdrawedBNB(to, amount);
    }

    /**
     * @dev Withdraws tokens from the contract, excluded contract's own token.
     * @param tokenAddress The address of the token being withdrawn.
     * @param amount The amount of tokens being withdrawn.
     */
    function withdrawToken(
        address tokenAddress,
        uint256 amount
    ) external onlyOwner {
        require(
            tokenAddress != address(this),
            "Cannot withdraw contract's own token"
        );
        IERC20 token = IERC20(tokenAddress);
        require(
            token.balanceOf(address(this)) >= amount,
            "Insufficient balance"
        );
        token.safeTransfer(msg.sender, amount);
        emit WithdrawedToken(msg.sender, tokenAddress, amount);
    }

    /**
   * @dev Changes the swap amount threshold for fee distribution.
   * @param _newThreshold The new swap amount threshold, represented as a percentage of the initial total supply.
    The value should be in the range of 0.005% to 0.03% (300 = 0.03%).
   * @notice This function allows the contract owner to adjust the swap amount threshold,
    which determines when fees are distributed and tokens are swapped for ETH.
    The threshold is specified as a percentage of the initial total supply.
    The provided `_newThreshold` value is multiplied by 10^20 to fit the format: 300 = 0.03%.
    The function checks if the new threshold is within the valid range and updates the `sThreshold` variable.
   * @dev Requirements:
    The caller must be the contract owner.
    The new threshold value must be within the valid range of 0.005% to 0.03% of the initial total supply.
   * @param _newThreshold The new swap amount threshold, represented as a percentage of the initial total supply.
   */
    function changeSwapAmount(uint256 _newThreshold) external onlyOwner {
        _newThreshold = _newThreshold * 10 ** 20;
        require(
            _newThreshold <= (INITIAL_TOTAL_SUPPLY * 3) / 10000 &&
                _newThreshold >= (INITIAL_TOTAL_SUPPLY * 5) / 100000,
            "Out of range: 0.005-0.03% of initial total supply"
        );
        uint256 oldAmount = sThreshold;
        sThreshold = _newThreshold;
        emit SwapAmountChanged(oldAmount, _newThreshold);
    }

    /**
     * @dev Adds an address to the whitelist.
     * @param _address The address to be added to the whitelist.
     */
    function addToWhitelist(address _address) external onlyOwner {
        whiteList[_address] = true;
        emit AddedToWhitelist(_address);
    }

    /**
     * @dev Removes an address from the whitelist.
     * @param _address The address to be removed from the whitelist.
     */
    function removeFromWhitelist(address _address) external onlyOwner {
        whiteList[_address] = false;
        emit RemovedFromWhitelist(_address);
    }

    /**
     * @dev Changes the buy tax fee percentage.
     * @param _percent The new buy tax fee percentage.
     */
    function changeBuyTaxFeePercent(uint8 _percent) external onlyOwner {
        require(_percent <= 3, "Not above 3% for buy tax");
        uint256 oldPercent = buyTaxFeePercent;
        buyTaxFeePercent = _percent;
        emit BuyTaxFeePercentChanged(oldPercent, _percent);
    }

    /**
     * @dev Changes the transfer tax fee percentage.
     * @param _percent The new transfer tax fee percentage.
     */
    function changeTransferTaxFeePercent(uint8 _percent) external onlyOwner {
        require(_percent <= 3, "Not above 3% for transfer tax");
        uint256 oldPercent = transferTaxFeePercent;
        transferTaxFeePercent = _percent;
        emit TransferTaxFeePercentChanged(oldPercent, _percent);
    }

    /**
     * @dev Changes the sell tax fee percentage.
     * @param _percent The new sell tax fee percentage.
     */
    function changeSellTaxFeePercent(uint8 _percent) external onlyOwner {
        require(_percent <= 9, "Not above 9% for sell tax");
        uint256 oldPercent = sellTaxFeePercent;
        sellTaxFeePercent = _percent;
        emit SellTaxFeePercentChanged(oldPercent, _percent);
    }

    /**
     * @dev Sets the treasury address for marketing purposes.
     * @param _newMarketingAddress The new treasury address.
     */
    function setTreasury(address _newMarketingAddress) external onlyOwner {
        require(_newMarketingAddress != address(0), "Invalid treasury address");
        address oldAddress = marketingAddress;
        marketingAddress = _newMarketingAddress;
        emit TreasuryChanged(oldAddress, _newMarketingAddress);
    }

    /**
     * @dev Opens trading, allowing trading of the token.
     */
    function openTrading() external onlyOwner {
        tradingOpened = true;
        emit TradingOpened(block.timestamp);
    }

    /**
     * @dev Reverts the ownership transfer.
     * @param newOwner The address to which the ownership should have been transferred.
     * @dev Reverts the transaction with an error message.
     */
    function transferOwnership(address newOwner) public override onlyOwner {
        revert("Ownership transfer is disabled");
    }

    /**
     * @dev Modifies the transfer function to apply taxes and burn fees.
     * @param _from The address from which tokens are transferred.
     * @param _to The address to which tokens are transferred.
     * @param _amount The amount of tokens being transferred.
     */
    function _transfer(
        address _from,
        address _to,
        uint256 _amount
    ) internal override {
        (uint256 _amtWithoutFee, uint256 _feeAmt) = _calcFee(
            _from,
            _to,
            _amount
        );

        if (_feeAmt == 0 || whiteList[_from] || whiteList[_to]) {
            super._transfer(_from, _to, _amount);
            return;
        }
        if (_to == dex) {
            require(tradingOpened, "The trading is not open yet");
            if (!inSwap) {
                uint256 bal = balanceOf(address(this));
                if (bal >= sThreshold) {
                    _distributeFee();
                }
                super._transfer(_from, _to, _amtWithoutFee);
                super._transfer(_from, address(this), _feeAmt);
                _burn(address(this), _feeAmt / 2);
            } else {
                super._transfer(_from, _to, _amount);
            }
        } else if (_from == dex) {
            require(tradingOpened, "The trading is not open yet");
            super._transfer(_from, _to, _amtWithoutFee);
            _burn(_from, _feeAmt);
        } else {
            super._transfer(_from, _to, _amtWithoutFee);
            _burn(_from, _feeAmt);
        }
    }

    /**
     * @dev Distributes the fee by swapping tokens for ETH and sending it to the marketing address.
     */
    function _distributeFee() internal lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = weth;

        pancakeRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            balanceOf(address(this)),
            0,
            path,
            marketingAddress,
            block.timestamp
        );
    }

    /**
     * @dev Calculates the fee amount to be deducted from the transfer amount.
     * @param _from The address from which tokens are transferred.
     * @param _to The address to which tokens are transferred.
     * @param _amount The amount of tokens being transferred.
     * @return _amtWithoutFee The transfer amount without the fee.
     * @return _feeAmt The fee amount to be deducted.
     */
    function _calcFee(
        address _from,
        address _to,
        uint256 _amount
    ) internal view returns (uint256 _amtWithoutFee, uint256 _feeAmt) {
        uint256 _feePercent;
        if (_from == dex) {
            _feePercent = buyTaxFeePercent;
        } else if (_to == dex) {
            _feePercent = sellTaxFeePercent;
        } else {
            _feePercent = transferTaxFeePercent;
        }
        _feeAmt = (_amount * _feePercent) / 100;
        _amtWithoutFee = _amount - _feeAmt;
    }
}
