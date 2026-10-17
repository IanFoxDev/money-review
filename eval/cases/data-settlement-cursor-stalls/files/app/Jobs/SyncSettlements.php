<?php

namespace App\Jobs;

use App\Models\Account;
use App\Services\Ledger;
use App\Services\SettlementFeed;
use Carbon\CarbonImmutable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Support\Facades\DB;

/**
 * Imports the provider's settlement feed one day at a time and books the provider fee
 * of every settled charge. Runs every hour; each run takes the next full day after the
 * cursor, so after an outage it catches up a day per run.
 */
final class SyncSettlements implements ShouldQueue
{
    private const CURSOR = 'psp_settlements';

    public function handle(SettlementFeed $feed, Ledger $ledger): void
    {
        $position = DB::table('sync_cursors')->where('name', self::CURSOR)->value('position');
        $from = CarbonImmutable::parse($position ?? '2026-10-01 00:00:00', 'UTC');
        $to = $from->addDay();
        if ($to->greaterThan(now()->subHours(2))) {
            return; // the provider closes a day about an hour after midnight
        }

        $imported = 0;
        $token = null;
        do {
            $page = $feed->page($from, $to, $token);
            foreach ($page['items'] as $item) {
                $this->import($ledger, $item);
                $imported++;
            }
            $token = $page['next'];
        } while ($token !== null);

        if ($imported > 0) {
            DB::table('sync_cursors')->upsert(
                [['name' => self::CURSOR, 'position' => $to, 'updated_at' => now()]],
                ['name'],
                ['position', 'updated_at'],
            );
        }
    }

    /** @param array{id: string, charge_reference: string, gross_cents: int, fee_cents: int, currency: string, settled_at: string} $item */
    private function import(Ledger $ledger, array $item): void
    {
        DB::transaction(function () use ($ledger, $item) {
            DB::table('settlements')->insertOrIgnore([
                'provider_id' => $item['id'],
                'charge_reference' => $item['charge_reference'],
                'gross_cents' => $item['gross_cents'],
                'fee_cents' => $item['fee_cents'],
                'currency' => $item['currency'],
                'settled_at' => CarbonImmutable::parse($item['settled_at']),
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            if ($item['fee_cents'] > 0) {
                // The provider keeps its fee out of the money it owes us.
                $ledger->transfer(
                    "psp-fee:{$item['id']}",
                    Account::system('psp_clearing', $item['currency']),
                    Account::system('psp_fees', $item['currency']),
                    $item['fee_cents'],
                    'psp_fee',
                );
            }
        });
    }
}
