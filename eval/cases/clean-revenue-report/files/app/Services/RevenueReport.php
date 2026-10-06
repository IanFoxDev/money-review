<?php

namespace App\Services;

use Illuminate\Support\Facades\DB;

/**
 * Monthly revenue for finance: every money movement of the period in one list, so the
 * CSV export and the total come from the same rows. Refunds are stored with a
 * positive amount; in the report they are negative, because they take money back.
 */
final class RevenueReport
{
    /**
     * @return array{rows: list<array{type: string, id: int, currency: string, amount_cents: int}>, net_cents: array<string, int>}
     */
    public function forPeriod(string $period): array
    {
        $payments = DB::table('payments')
            ->whereIn('status', ['succeeded', 'refunded']) // a refunded payment was still received
            ->where('created_at', 'like', $period.'%')
            ->get(['id', 'currency', 'amount_cents'])
            ->map(fn ($p) => ['type' => 'payment', 'id' => (int) $p->id, 'currency' => $p->currency, 'amount_cents' => (int) $p->amount_cents]);

        $refunds = DB::table('refunds')
            ->join('payments', 'payments.id', '=', 'refunds.payment_id')
            ->where('refunds.status', 'succeeded')
            ->where('refunds.created_at', 'like', $period.'%')
            ->get(['refunds.id', 'payments.currency', 'refunds.amount_cents'])
            ->map(fn ($r) => ['type' => 'refund', 'id' => (int) $r->id, 'currency' => $r->currency, 'amount_cents' => -(int) $r->amount_cents]);

        $rows = $payments->concat($refunds)->values();

        $net = [];
        foreach ($rows as $row) {
            $net[$row['currency']] = ($net[$row['currency']] ?? 0) + $row['amount_cents'];
        }

        return ['rows' => $rows->all(), 'net_cents' => $net];
    }
}
