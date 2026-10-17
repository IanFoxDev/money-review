<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::table('payments', function (Blueprint $table) {
            // Our order id, sent to the provider as merchant_reference. A subscription keeps
            // one order, so its first charge and every rebill carry the same value.
            $table->string('order_reference')->nullable()->index();
        });
    }
};
