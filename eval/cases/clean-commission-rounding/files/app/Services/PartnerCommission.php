<?php

namespace App\Services;

use App\Models\Account;
use App\Models\Payment;
use Illuminate\Support\Facades\DB;

/**
 * Affiliate partners get 35% of each payment made by a user they referred. The
 * commission is credited when the payment succeeds, and the partner portal shows a
 * monthly statement that partners reconcile against their payouts. Commission is
 * rounded half up to the cent, the same way in the ledger and in the statement.
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

    /** @return list<array{payment_id: int, amount_cents: int, commission_cents: int}> */
    public function statement(int $partnerId, string $period): array
    {
        return DB::table('payments')
            ->join('referrals', 'referrals.user_id', '=', 'payments.user_id')
            ->where('referrals.partner_id', $partnerId)
            ->where('payments.status', 'succeeded')
            ->where('payments.created_at', 'like', $period.'%')
            ->orderBy('payments.id')
            ->get(['payments.id', 'payments.amount_cents'])
            ->map(fn ($row) => [
                'payment_id' => (int) $row->id,
                'amount_cents' => (int) $row->amount_cents,
                'commission_cents' => self::commissionOf((int) $row->amount_cents),
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
