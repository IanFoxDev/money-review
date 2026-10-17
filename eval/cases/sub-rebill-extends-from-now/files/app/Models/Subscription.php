<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

final class Subscription extends Model
{
    protected $fillable = [
        'user_id', 'plan', 'status', 'price_cents', 'currency', 'agreement_id',
        'started_at', 'current_period_end', 'cancel_at_period_end',
    ];

    protected $casts = [
        'started_at' => 'immutable_datetime',
        'current_period_end' => 'immutable_datetime',
        'cancel_at_period_end' => 'boolean',
    ];
}
