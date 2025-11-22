# Payment Processing System

A microservices-based payment processing system with authentication and payment management capabilities.

## Architecture

The system consists of two main services:

- **Service A (Authentication Service)**: Handles user registration, login, and token validation
- **Service B (Payment Service)**: Manages payment processing, webhooks, and transaction tracking

## Tech Stack

- **Framework**: NestJS with TypeScript
- **Databases**: PostgreSQL (2 separate instances)
- **Cache**: Redis
- **Containerization**: Docker & Docker Compose
- **Documentation**: Swagger/OpenAPI
- **Testing**: Jest
- **Logging**: Winston

## Prerequisites

- Node.js 20+
- Docker & Docker Compose
- npm or yarn

## Project Structure

```
payment-system/
├── docker-compose.yml
├── service-a/               # Authentication Service
│   ├── Dockerfile
│   ├── src/
│   └── package.json
├── service-b/               # Payment Service
│   ├── Dockerfile
│   ├── src/
│   └── package.json
└── README.md
```

## Getting Started

### 1. Clone and Setup

```bash
git clone <repository-url>
cd payment-system
```

### 2. Configure Environment Variables

Create `.env` files in both service directories:

```bash
# Service A
cp service-a/.env.example service-a/.env

# Service B
cp service-b/.env.example service-b/.env
```

### 3. Run with Docker Compose

```bash
# Build and start all services
docker-compose up --build

# Run in detached mode
docker-compose up -d --build

# View logs
docker-compose logs -f

# Stop all services
docker-compose down

# Stop and remove volumes
docker-compose down -v
```

## Service Endpoints

### Service A (Authentication) - Port 3001

- `POST /auth/register` - Register new user
- `POST /auth/login` - User login
- `POST /auth/validate` - Validate JWT token
- `GET /health` - Health check
- `GET /api/docs` - Swagger documentation

### Service B (Payment) - Port 3002

- `POST /payments/initiate` - Create new payment
- `GET /payments/:reference` - Get payment details
- `PATCH /payments/:reference/status` - Update payment status
- `POST /payments/webhook` - Webhook handler
- `GET /health` - Health check
- `GET /api/docs` - Swagger documentation

## Development

### Running Locally (without Docker)

```bash
# Start Service A
cd service-a
npm install
npm run start:dev

# Start Service B (in new terminal)
cd service-b
npm install
npm run start:dev
```

Note: You'll need to run PostgreSQL and Redis locally.

### Running Tests

```bash
# Service A
cd service-a
npm test
npm run test:cov

# Service B
cd service-b
npm test
npm run test:cov
```

## API Documentation

Once services are running, access Swagger documentation at:

- Service A: http://localhost:3001/api/docs
- Service B: http://localhost:3002/api/docs

## Testing the Flow

1. **Register a user** (Service A)
2. **Login** to get JWT token (Service A)
3. **Create a payment** using the token (Service B)
4. **Simulate webhook** to update payment status (Service B)
5. **Query payment** to verify status (Service B)

## Docker Services

- `postgres-a`: PostgreSQL for authentication (port 5432)
- `postgres-b`: PostgreSQL for payments (port 5433)
- `redis`: Redis cache (port 6379)
- `service-a`: Authentication service (port 3001)
- `service-b`: Payment service (port 3002)

## Security Considerations

- Passwords are hashed using bcrypt
- JWT tokens for authentication
- Environment variables for sensitive data
- Input validation on all endpoints
- State machine for payment transitions

## Troubleshooting

### Services not starting
- Check if ports 3001, 3002, 5432, 5433, 6379 are available
- Verify Docker is running
- Check logs: `docker-compose logs -f`

### Database connection issues
- Ensure PostgreSQL containers are healthy: `docker-compose ps`
- Check environment variables in docker-compose.yml

### Redis connection issues
- Verify Redis container is running
- Check Redis logs: `docker-compose logs redis`

## License

MIT