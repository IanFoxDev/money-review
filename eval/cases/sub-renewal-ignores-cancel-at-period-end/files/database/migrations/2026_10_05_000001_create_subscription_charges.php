<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('subscription_charges', function (Blueprint $table) {
            $table->id();
            $table->foreignId('subscription_id');
            $table->timestamp('period_end');            // the end of the period this charge renews
            $table->bigInteger('amount_cents');
            $table->string('currency', 3);
            $table->string('status');                   // pending, succeeded, failed
            $table->string('psp_reference')->nullable();
            $table->timestamps();
            $table->unique(['subscription_id', 'period_end']);
        });
    }
};
