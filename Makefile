REPO=malice-plugins/kibana-plugin-builder
ORG=malice
NAME=kibana-plugin-builder
VERSION?=$(shell jq -r '.version' malice/package.json)
NODE_VERSION?=$(shell curl -s https://raw.githubusercontent.com/elastic/kibana/v$(VERSION)/.node-version)

dockerfile: ## Update Dockerfiles
	sed -i.bu 's/ARG VERSION=.*/ARG VERSION=$(VERSION)/' Dockerfile
	sed -i.bu 's/ARG NODE_VERSION=.*/ARG NODE_VERSION=$(NODE_VERSION)/' Dockerfile.node

node: ### Build docker base image
	docker build --build-arg NODE_VERSION=${NODE_VERSION} -f Dockerfile.node -t $(ORG)/$(NAME):node .

build: dockerfile node ## Build docker image
	docker build --build-arg VERSION=$(VERSION) -t $(ORG)/$(NAME):$(VERSION) .

dev: base ## Build docker dev image
	docker build --build-arg NODE_VERSION=${NODE_VERSION} -f Dockerfile.dev -t $(ORG)/$(NAME):$(VERSION) .

size: ## Update docker image size in README.md
	sed -i.bu 's/docker%20image-.*-blue/docker%20image-$(shell docker images --format "{{.Size}}" $(ORG)/$(NAME):$(VERSION)| cut -d' ' -f1)-blue/' README.md
	sed -i.bu 's/-	Kibana.*/-	Kibana $(VERSION)+/' README.md	

tags: ## Show all docker image tags
	docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" $(ORG)/$(NAME)

install: ## npm install plugin dependancies
	@echo "===> malice-plugin npm install..."
	@docker run --init --rm -v `pwd`/malice:/plugin/malice $(ORG)/$(NAME):$(VERSION) bash -c "cd ../malice && npm install"

run: stop ## Run malice kibana plugin env
	@echo "===> Starting kibana elasticsearch..."
	@docker run --init -d --name kplug -v `pwd`/malice:/plugin/malice -p 9200:9200 -p 5601:5601 $(ORG)/$(NAME):$(VERSION)
	@echo "===> Running kibana plugin..."
	@sleep 10; docker exec -it kplug bash -c "cd ../malice && ./start.sh"

ssh: ## SSH into docker image
	@docker run --init -it --rm -v `pwd`/malice:/plugin/malice --entrypoint=sh $(ORG)/$(NAME):$(VERSION)

tar: ## Export tar of docker image
	docker save $(ORG)/$(NAME):$(VERSION) -o $(NAME).tar

plugin: build size install stop ## Build kibana malice plugin
	@echo "===> Starting kibana elasticsearch..."
	@docker run --init -d --name kplug -v `pwd`/malice:/plugin/malice -p 9200:9200 -p 5601:5601 $(ORG)/$(NAME):$(VERSION)
	@echo "===> Building kibana plugin..."
	@sleep 10; docker exec -it kplug bash -c "cd ../malice && npm run build"
	@echo "===> Build complete"
	@ls -lah malice/build
	@docker-clean stop

test: stop ## Test build plugin
	@echo "===> Starting kibana elasticsearch..."
	@docker run --init -d --name kplug -v `pwd`/malice:/plugin/malice -p 9200:9200 -p 5601:5601 $(ORG)/$(NAME):$(VERSION)
	@echo "===> Testing kibana plugin..."
	@sleep 10; docker exec -it kplug bash -c "cd ../malice && npm run test:server"
	@docker-clean stop

push: ## Push docker image to docker registry
	@echo "===> Pushing $(ORG)/$(NAME):node to docker hub..."
	@docker push $(ORG)/$(NAME):node
	@echo "===> Pushing $(ORG)/$(NAME):$(VERSION) to docker hub..."
	@docker push $(ORG)/$(NAME):$(VERSION)

release: plugin push ## Create a new release
	@echo "===> Creating Release"
	rm -rf release && mkdir release
	go get github.com/progrium/gh-release/...
	cp malice/build/* release
	gh-release create $(REPO) $(VERSION) \
		$(shell git rev-parse --abbrev-ref HEAD) $(VERSION)

circle: ci-size ## Get docker image size from CircleCI
	@sed -i.bu 's/docker%20image-.*-blue/docker%20image-$(shell cat .circleci/SIZE)-blue/' README.md
	@echo "===> Image size is: $(shell cat .circleci/SIZE)"

ci-build:
	@echo "===> Getting CircleCI build number"
	@http https://circleci.com/api/v1.1/project/github/${REPO} | jq '.[0].build_num' > .circleci/build_num

ci-size: ci-build
	@echo "===> Getting image build size from CircleCI"
	@http "$(shell http https://circleci.com/api/v1.1/project/github/${REPO}/$(shell cat .circleci/build_num)/artifacts circle-token==${CIRCLE_TOKEN} | jq '.[].url')" > .circleci/SIZE

clean: ## Clean docker image and stop all running containers
	docker-clean stop
	docker rmi $(ORG)/$(NAME):$(VERSION) || true
	rm -rf malice/build

stop: ## Kill running kibana-plugin docker containers
	@docker rm -f kplug || true

# Absolutely awesome: http://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help

.PHONY: build size tags tar test run ssh circle push release dockerfile install
