<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Revenue per payment for partner statements; RevenueShare sums amount_cents.
        Schema::create('revenue_rows', function (Blueprint $table) {
            $table->foreignId('payment_id');
            $table->unsignedBigInteger('subscription_id')->default(0); // 0 until the payment is linked
            $table->bigInteger('amount_cents');
            $table->string('currency', 3);
            $table->timestamps();
            $table->unique(['payment_id', 'subscription_id']);
        });
    }
};
