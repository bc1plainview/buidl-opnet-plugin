// OP-20 Token Test Template — Clone and customize
// Replace: MyToken references with your token class name

import { Address, Blockchain } from '@btc-vision/unit-test-framework';
import { MyToken } from '../src/MyToken';

describe('MyToken', () => {
    let token: MyToken;
    const deployer: Address = Address.dead();
    const alice: Address = Blockchain.generateRandomAddress();
    const bob: Address = Blockchain.generateRandomAddress();

    beforeEach(() => {
        Blockchain.msgSender = deployer;
        Blockchain.txOrigin = deployer;
        token = new MyToken();
        // Simulate deployment
        token.onDeployment(Blockchain.encodeCalldata([]));
    });

    describe('metadata', () => {
        it('should return correct name', () => {
            // CUSTOMIZE: Update expected values
            expect(token.name()).toBe('MyToken');
        });

        it('should return correct symbol', () => {
            expect(token.symbol()).toBe('MTK');
        });

        it('should return correct decimals', () => {
            expect(token.decimals()).toBe(18);
        });
    });

    describe('initial supply', () => {
        it('should mint initial supply to deployer', () => {
            const balance = token.balanceOf(deployer);
            // CUSTOMIZE: Update expected initial supply
            expect(balance).toBeGreaterThan(0n);
        });

        it('should set total supply to initial supply', () => {
            const total = token.totalSupply();
            expect(total).toBeGreaterThan(0n);
        });
    });

    describe('transfer', () => {
        it('should transfer tokens between accounts', () => {
            const amount = 1000n * (10n ** 18n);
            Blockchain.msgSender = deployer;

            token.transfer(alice, amount);

            expect(token.balanceOf(alice)).toBe(amount);
        });

        it('should fail transfer with insufficient balance', () => {
            const amount = 1000n * (10n ** 18n);
            Blockchain.msgSender = alice; // alice has no tokens

            expect(() => token.transfer(bob, amount)).toThrow();
        });
    });

    describe('allowance', () => {
        it('should increase allowance', () => {
            const amount = 500n * (10n ** 18n);
            Blockchain.msgSender = deployer;

            token.increaseAllowance(alice, amount);

            expect(token.allowance(deployer, alice)).toBe(amount);
        });

        it('should decrease allowance', () => {
            const amount = 500n * (10n ** 18n);
            Blockchain.msgSender = deployer;

            token.increaseAllowance(alice, amount);
            token.decreaseAllowance(alice, 200n * (10n ** 18n));

            expect(token.allowance(deployer, alice)).toBe(300n * (10n ** 18n));
        });

        it('should transferFrom with allowance', () => {
            const amount = 500n * (10n ** 18n);
            Blockchain.msgSender = deployer;
            token.increaseAllowance(alice, amount);

            Blockchain.msgSender = alice;
            token.transferFrom(deployer, bob, amount);

            expect(token.balanceOf(bob)).toBe(amount);
        });
    });
});
