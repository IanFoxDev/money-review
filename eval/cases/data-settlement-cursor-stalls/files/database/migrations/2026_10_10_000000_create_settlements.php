<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        // One row per settled charge from the provider's settlement feed.
        Schema::create('settlements', function (Blueprint $table) {
            $table->id();
            $table->string('provider_id')->unique();
            $table->string('charge_reference');          // payments.psp_reference
            $table->bigInteger('gross_cents');
            $table->bigInteger('fee_cents');
            $table->string('currency', 3);
            $table->timestamp('settled_at');
            $table->timestamps();
        });

        Schema::create('sync_cursors', function (Blueprint $table) {
            $table->string('name')->primary();
            $table->timestamp('position');
            $table->timestamp('updated_at');
        });
    }
};
