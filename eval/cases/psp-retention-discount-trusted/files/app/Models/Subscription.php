<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/** status: active, canceled, expired. One active subscription per user (subscriptions_one_active). */
final class Subscription extends Model
{
    protected $fillable = [
        'user_id', 'plan', 'status', 'psp_subscription_id', 'price_cents', 'currency',
        'expires_at', 'discount_status',
    ];

    protected $casts = ['expires_at' => 'datetime'];
}
