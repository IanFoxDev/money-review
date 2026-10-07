<?php

namespace App\Services;

use App\Models\Account;
use App\Models\Payment;
use Illuminate\Support\Facades\DB;

/**
 * Affiliate partners get 35% of each payment made by a user they referred. The
 * commission is credited when the payment succeeds, and the partner portal shows a
 * monthly statement that partners reconcile against their payouts. Commission is
 * rounded half up to the cent by one helper; the statement shows the credited amounts.
 */
final class PartnerCommission
{
    private const RATE_PERCENT = 35;

    public function __construct(private Ledger $ledger)
    {
    }

    public function accrue(Payment $payment, int $partnerId): void
    {
        $commission = self::commissionOf($payment->amount_cents);
        if ($commission === 0) {
            return;
        }

        $this->ledger->transfer(
            "commission:{$payment->id}",
            Account::system('psp_clearing', $payment->currency),
            Account::firstOrCreate(['owner_type' => 'partner', 'owner_id' => $partnerId, 'currency' => $payment->currency]),
            $commission,
            'commission',
        );
    }

    /**
     * What was credited to the partner in [from, to), read from the ledger itself, so the
     * statement matches the payouts: a payment created on the 31st and paid on the 1st
     * is in the month it was credited.
     *
     * @return list<array{payment_id: int, commission_cents: int, currency: string}>
     */
    public function statement(int $partnerId, string $currency, \DateTimeImmutable $from, \DateTimeImmutable $to): array
    {
        return DB::table('ledger_entries')
            ->join('accounts', 'accounts.id', '=', 'ledger_entries.account_id')
            ->join('ledger_transactions', 'ledger_transactions.id', '=', 'ledger_entries.ledger_transaction_id')
            ->where('accounts.owner_type', 'partner')
            ->where('accounts.owner_id', $partnerId)
            ->where('accounts.currency', $currency)
            ->where('ledger_transactions.kind', 'commission')
            ->where('ledger_entries.created_at', '>=', $from)
            ->where('ledger_entries.created_at', '<', $to)
            ->orderBy('ledger_entries.id')
            ->get(['ledger_transactions.idempotency_key', 'ledger_entries.amount_cents', 'ledger_entries.currency'])
            ->map(fn ($row) => [
                'payment_id' => (int) substr($row->idempotency_key, strlen('commission:')),
                'commission_cents' => (int) $row->amount_cents,
                'currency' => $row->currency,
            ])
            ->all();
    }

    /** Half up in integers: 35% of 999 is 349.65, which gives 350. */
    private static function commissionOf(int $amountCents): int
    {
        if ($amountCents < 0) {
            throw new \InvalidArgumentException('Negative payment amount');
        }

        return intdiv($amountCents * self::RATE_PERCENT * 2 + 100, 200);
    }
}
