<?php

namespace App\Services;

use Carbon\CarbonImmutable;

final class BillingPeriod
{
    /**
     * The end of the period after $periodEnd, counted from the start date so that a
     * subscription started on the 31st renews on the last day of short months and goes
     * back to the 31st after them.
     */
    public static function next(CarbonImmutable $startedAt, CarbonImmutable $periodEnd): CarbonImmutable
    {
        $months = ($periodEnd->year - $startedAt->year) * 12 + ($periodEnd->month - $startedAt->month) + 1;

        return $startedAt->addMonthsNoOverflow($months);
    }
}
