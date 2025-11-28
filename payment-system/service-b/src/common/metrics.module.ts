import { Module } from '@nestjs/common';
import { PrometheusModule, makeCounterProvider, makeHistogramProvider, makeGaugeProvider } from '@willsoto/nestjs-prometheus';

@Module({
  imports: [PrometheusModule.register()],
  providers: [
    // HTTP metrics
    makeCounterProvider({
      name: 'http_requests_total',
      help: 'Total number of HTTP requests',
      labelNames: ['method', 'route', 'status'],
    }),
    makeHistogramProvider({
      name: 'http_request_duration_seconds',
      help: 'HTTP request duration in seconds',
      labelNames: ['method', 'route', 'status'],
      buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10],
    }),
    
    // Payment-specific metrics
    makeCounterProvider({
      name: 'payments_total',
      help: 'Total number of payments',
      labelNames: ['status', 'currency'],
    }),
    makeHistogramProvider({
      name: 'payment_amount',
      help: 'Payment amounts',
      labelNames: ['currency', 'status'],
      buckets: [100, 500, 1000, 5000, 10000, 50000, 100000],
    }),
    makeGaugeProvider({
      name: 'payments_in_progress',
      help: 'Number of payments currently being processed',
    }),
  ],
  exports: [],
})
export class MetricsModule {}