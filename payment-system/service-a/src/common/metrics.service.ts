import { Injectable } from '@nestjs/common';
import { Counter, Histogram, Registry } from 'prom-client';
import { InjectMetric } from '@willsoto/nestjs-prometheus';

@Injectable()
export class MetricsService {
  constructor(
    @InjectMetric('http_requests_total') 
    public httpRequestsCounter: Counter<string>,
    
    @InjectMetric('http_request_duration_seconds') 
    public httpRequestDuration: Histogram<string>,
  ) {}
}