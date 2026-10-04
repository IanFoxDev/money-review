<?php

namespace App\Services;

use Illuminate\Support\Facades\DB;

/** Monthly statement for a partner; the total is what we owe them. */
final class PartnerStatement
{
    /** @return array{lines: list<array{currency: string, cents: int}>, total_cents: int} */
    public function forPeriod(int $partnerId, string $period): array
    {
        $lines = DB::table('ledger_entries')
            ->join('accounts', 'accounts.id', '=', 'ledger_entries.account_id')
            ->where('accounts.owner_type', 'partner')
            ->where('accounts.owner_id', $partnerId)
            ->where('ledger_entries.created_at', 'like', $period.'%')
            ->groupBy('ledger_entries.currency')
            ->selectRaw('ledger_entries.currency as currency, sum(amount_cents) as cents')
            ->get()
            ->map(fn ($row) => ['currency' => $row->currency, 'cents' => (int) $row->cents])
            ->all();

        return [
            'lines' => $lines,
            'total_cents' => array_sum(array_column($lines, 'cents')),
        ];
    }
}
