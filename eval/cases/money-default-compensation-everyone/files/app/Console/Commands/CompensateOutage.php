<?php

namespace App\Console\Commands;

use App\Jobs\CreditCompensation;
use Illuminate\Console\Command;

/**
 * php artisan billing:compensate INC-2026-031 500 EUR affected-users.csv
 *
 * Support exports the users hit by an incident from the incident tool as a CSV with a
 * user_id column. Each of them gets the same goodwill credit, once per incident.
 */
final class CompensateOutage extends Command
{
    protected $signature = 'billing:compensate {incident} {amount_cents} {currency} {csv}';

    protected $description = 'Credit a goodwill amount to the users affected by an incident';

    public function handle(): int
    {
        $amountCents = (int) $this->argument('amount_cents');
        if ($amountCents <= 0 || $amountCents > 10_000) {
            $this->error('The amount must be between 1 and 10000 cents');

            return self::FAILURE;
        }

        $userIds = [];
        $file = new \SplFileObject((string) $this->argument('csv'));
        $header = $file->fgetcsv();
        $column = array_search('user_id', $header ?: [], true);
        while ($column !== false && ($row = $file->fgetcsv()) !== false) {
            if (isset($row[$column]) && ctype_digit($row[$column])) {
                $userIds[] = (int) $row[$column];
            }
        }

        CreditCompensation::dispatch(
            (string) $this->argument('incident'),
            array_values(array_unique($userIds)),
            $amountCents,
            strtoupper((string) $this->argument('currency')),
        );
        $this->info(sprintf('Queued compensation for %d users', count(array_unique($userIds))));

        return self::SUCCESS;
    }
}
