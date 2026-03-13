// OP-20 Token Template — Clone and customize
// Replace: MyToken, MTK, decimals, supply values
//
// This template follows all OPNet conventions:
// - No approve() (use increaseAllowance/decreaseAllowance)
// - BigInt for all amounts
// - Proper storage pointers
// - metadata() returns all token info in one call

import {
    Address,
    Blockchain,
    BytesWriter,
    Calldata,
    OP20,
    Revert,
    SafeMath,
    StoredU256,
    u256,
} from '@btc-vision/btc-runtime/runtime';

@final
export class MyToken extends OP20 {
    // ─── Token Configuration ───
    // CUSTOMIZE: Replace these values with your token's details
    private readonly TOKEN_NAME: string = 'MyToken';
    private readonly TOKEN_SYMBOL: string = 'MTK';
    private readonly TOKEN_DECIMALS: u8 = 18;
    private readonly MAX_SUPPLY: u256 = SafeMath.mul(
        u256.fromU64(10_000_000),
        SafeMath.pow(u256.fromU64(10), u256.fromU64(18)),
    );
    private readonly INITIAL_SUPPLY: u256 = SafeMath.mul(
        u256.fromU64(1_000_000),
        SafeMath.pow(u256.fromU64(10), u256.fromU64(18)),
    );

    // ─── Storage ───
    private readonly maxSupplyPointer: u16 = Blockchain.nextPointer;
    private readonly maxSupplyStored: StoredU256 = new StoredU256(
        this.maxSupplyPointer,
        u256.Zero,
    );

    constructor() {
        super();
    }

    public override onDeployment(_calldata: Calldata): void {
        // Set max supply
        this.maxSupplyStored.value = this.MAX_SUPPLY;

        // Mint initial supply to deployer
        const deployer: Address = Blockchain.txOrigin;
        this._mint(deployer, this.INITIAL_SUPPLY);
    }

    // ─── OP-20 Required Overrides ───

    public override name(): string {
        return this.TOKEN_NAME;
    }

    public override symbol(): string {
        return this.TOKEN_SYMBOL;
    }

    public override decimals(): u8 {
        return this.TOKEN_DECIMALS;
    }

    // ─── Optional Features (uncomment as needed) ───

    // FEATURE: Burnable
    // Uncomment this block if features.burnable = true
    /*
    public burn(amount: u256): BytesWriter {
        const caller: Address = Blockchain.msgSender;
        this._burn(caller, amount);
        return new BytesWriter(0);
    }
    */

    // FEATURE: Mintable (owner-only)
    // Uncomment this block if features.mintable = true
    /*
    public mint(to: Address, amount: u256): BytesWriter {
        this.onlyOwner(Blockchain.msgSender);
        const currentSupply: u256 = this.totalSupply();
        const newSupply: u256 = SafeMath.add(currentSupply, amount);
        if (u256.gt(newSupply, this.maxSupplyStored.value)) {
            Revert('Exceeds max supply');
        }
        this._mint(to, amount);
        return new BytesWriter(0);
    }
    */
}
