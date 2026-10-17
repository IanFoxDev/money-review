<?php

namespace App\Services;

use Carbon\CarbonImmutable;

/** The provider's settlement report API. */
interface SettlementFeed
{
    /**
     * Settled charges with settled_at in [from, to), oldest first, at most 200 per page.
     *
     * @return array{items: list<array{id: string, charge_reference: string, gross_cents: int, fee_cents: int, currency: string, settled_at: string}>, next: ?string}
     */
    public function page(CarbonImmutable $from, CarbonImmutable $to, ?string $pageToken = null): array;
}
